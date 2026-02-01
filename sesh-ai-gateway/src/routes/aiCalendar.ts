import { Router, Request } from 'express';
import { FieldValue, Timestamp } from 'firebase-admin/firestore';

import { extractTextFromPdf } from '../services/docExtract';
import { callTextModel } from '../services/modelRouter';
import { aiLogsCollection, userCalendarEventsCollection } from '../services/firestoreService';
import { downloadFileFromSignedUrl } from '../services/storageService';
import { calendarColors, normalizeEventType, type CalendarEventType, type CalendarColorKey } from '../utils/calendarColors';
import { config } from '../utils/env';

type CalendarImportRequest = {
  userId?: string;
  timetablePdfSignedUrl: string;
  termStartDate?: string;
  timezone: string;
};

type CalendarEventOutput = {
  title: string;
  type: CalendarEventType;
  subjectCode?: string;
  startDateTime: string;
  endDateTime: string;
  venue?: string;
  colorKey: CalendarColorKey;
  recurrence?: string;
};

type CalendarReminder = {
  eventId: string;
  remindAt: string;
  message: string;
};

type CalendarImportResponse = {
  eventsCreated: number;
  events: CalendarEventOutput[];
  reminders: CalendarReminder[];
};

type PolicyGateInput = {
  userId?: string;
  text: string;
  contextType: 'calendar';
  contentHint?: string;
};

type PolicyGateResponse = {
  allowed: boolean;
  category: 'school' | 'non_school' | 'unknown';
  intent: 'socratic_help' | 'answer_seeking' | 'content_generation' | 'other';
  recommendTutor: boolean;
  reason?: 'school_only' | 'rate_limited' | 'blocked';
  nextStep?: string;
};

type NormalizedEvent = {
  title: string;
  type: CalendarEventType;
  subjectCode?: string;
  startDateTime: string;
  endDateTime: string;
  venue?: string;
  recurrence?: string;
};

const router = Router();

function safeJsonParse(text: string): Record<string, unknown> | null {
  try {
    return JSON.parse(text);
  } catch {
    const match = text.match(/\{[\s\S]*\}/);
    if (!match) return null;
    try {
      return JSON.parse(match[0]);
    } catch {
      return null;
    }
  }
}

function normalizeString(value: unknown, fallback = ''): string {
  const text = String(value ?? '').trim();
  return text.length ? text : fallback;
}

function normalizeEvents(raw: unknown): NormalizedEvent[] {
  if (!Array.isArray(raw)) return [];
  return raw
    .map((item) => {
      const event = item as Record<string, unknown>;
      const type = normalizeEventType(event.type);
      return {
        title: normalizeString(event.title, 'Timetable Event'),
        type,
        subjectCode: normalizeString(event.subjectCode, '') || undefined,
        startDateTime: normalizeString(event.startDateTime),
        endDateTime: normalizeString(event.endDateTime),
        venue: normalizeString(event.venue, '') || undefined,
        recurrence: normalizeString(event.recurrence, '') || undefined,
      };
    })
    .filter((event) => event.startDateTime && event.endDateTime);
}

function buildTablePayload(pages: { pageNumber: number; tables?: { rows: string[][] }[] }[]) {
  const rows: { pageNumber: number; rowIndex: number; columns: string[] }[] = [];
  pages.forEach((page) => {
    page.tables?.forEach((table) => {
      table.rows.forEach((row, rowIndex) => {
        const columns = row.map((cell) => String(cell ?? '').trim()).filter((cell) => cell.length > 0);
        if (columns.length > 0) rows.push({ pageNumber: page.pageNumber, rowIndex, columns });
      });
    });
  });
  return rows;
}

async function callPolicyGate(req: Request, payload: PolicyGateInput): Promise<PolicyGateResponse> {
  const authHeader = req.header('authorization') || '';
  const response = await fetch(`http://127.0.0.1:${config.port}/ai/policy/gate/calendar`, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: authHeader,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Policy gate failed ${response.status}: ${text}`);
  }

  return (await response.json()) as PolicyGateResponse;
}

async function logDecision(payload: Record<string, unknown>): Promise<void> {
  try {
    await aiLogsCollection().add({
      ...payload,
      createdAt: FieldValue.serverTimestamp(),
    });
  } catch (error) {
    console.error('Failed to log timetable import', error);
  }
}

function buildReminders(eventId: string, title: string, type: CalendarEventType, start: Date): CalendarReminder[] {
  const reminders: CalendarReminder[] = [];
  const baseReminder = new Date(start.getTime() - 30 * 60 * 1000);
  reminders.push({
    eventId,
    remindAt: baseReminder.toISOString(),
    message: `Upcoming ${type}: ${title} in 30 minutes`,
  });
  if (type === 'exam' || type === 'test') {
    const dayBefore = new Date(start.getTime() - 24 * 60 * 60 * 1000);
    reminders.push({
      eventId,
      remindAt: dayBefore.toISOString(),
      message: `${title} is tomorrow. Review your notes and prepare.`,
    });
  }
  return reminders;
}

router.post('/ai/calendar/importTimetable', async (req, res) => {
  const body = (req.body ?? {}) as CalendarImportRequest;
  const timetablePdfSignedUrl = body.timetablePdfSignedUrl?.trim();
  const termStartDate = body.termStartDate?.trim();
  const timezone = body.timezone?.trim();

  if (!timetablePdfSignedUrl || !timezone) {
    res.status(400).json({ error: 'invalid_request', message: 'timetablePdfSignedUrl and timezone are required.' });
    return;
  }

  const authedUserId = req.user?.uid;
  if (authedUserId && body.userId && body.userId !== authedUserId) {
    res.status(403).json({ error: 'user_mismatch' });
    return;
  }

  const userId = authedUserId || body.userId;
  if (!userId) {
    res.status(401).json({ error: 'missing_user' });
    return;
  }

  let pdfBuffer: Buffer;
  try {
    pdfBuffer = await downloadFileFromSignedUrl(timetablePdfSignedUrl);
  } catch (error) {
    console.error('Failed to download timetable PDF', error);
    res.status(502).json({ error: 'download_failed' });
    return;
  }

  let extracted;
  try {
    extracted = await extractTextFromPdf(pdfBuffer);
  } catch (error) {
    console.error('Document AI extraction failed', error);
    res.status(502).json({ error: 'doc_extract_failed' });
    return;
  }

  const tableRows = buildTablePayload(extracted.pages);
  const snippet = extracted.fullText.slice(0, 2000);

  let policy: PolicyGateResponse;
  try {
    policy = await callPolicyGate(req, {
      userId,
      text: snippet,
      contextType: 'calendar',
      contentHint: JSON.stringify({ termStartDate, timezone, rows: tableRows.length }),
    });
  } catch (error) {
    console.error('Policy gate error', error);
    res.status(502).json({ error: 'policy_gate_unavailable' });
    return;
  }

  if (!policy.allowed) {
    await logDecision({
      type: 'calendar_import',
      userId,
      allowed: false,
      reason: policy.reason ?? 'school_only',
      requestId: req.requestId || null,
    });
    res.status(403).json({
      error: 'policy_blocked',
      message: policy.nextStep || 'I can only import school-related timetables.',
    });
    return;
  }

  const provider = config.model.provider;
  const model = provider === 'openai' ? config.model.openai.model : config.model.google.model;
  const maxTokens = config.maxTokensPerEndpoint['POST /ai/calendar/importTimetable'];
  const systemPrompt = [
    'You normalize timetable rows into calendar events for students.',
    'Return JSON only with key: events (array).',
    'Each event: title, type, subjectCode, startDateTime, endDateTime, venue, recurrence.',
    'type must be one of: class, test, exam, tutorial, tutoring, meeting.',
    'Use timezone and termStartDate to resolve dates.',
    'Output ISO 8601 with timezone offset for startDateTime/endDateTime (e.g., 2026-02-10T09:00:00+02:00).',
    'If sessions repeat weekly, include recurrence as an RRULE string; otherwise omit.',
    'Do not include worked solutions or unrelated content.',
  ].join('\n');

  const userPayload = {
    termStartDate: termStartDate || null,
    timezone,
    tableRows,
    textSnippet: snippet,
  };

  const modelOutput = await callTextModel({
    provider,
    model,
    jsonOnly: true,
    temperature: 0.2,
    maxTokens,
    messages: [
      { role: 'system', content: systemPrompt },
      { role: 'user', content: JSON.stringify(userPayload) },
    ],
  });

  const parsed = safeJsonParse(modelOutput) ?? {};
  const normalized = normalizeEvents(parsed.events);

  const events: CalendarEventOutput[] = [];
  const reminders: CalendarReminder[] = [];

  for (const event of normalized) {
    const start = new Date(event.startDateTime);
    const end = new Date(event.endDateTime);
    if (!Number.isFinite(start.getTime()) || !Number.isFinite(end.getTime())) {
      continue;
    }
    if (end <= start) {
      continue;
    }

    const colorConfig = calendarColors[event.type];
    const collection = userCalendarEventsCollection(userId);
    const docRef = collection.doc();
    await docRef.set({
      title: event.title,
      start: Timestamp.fromDate(start),
      end: Timestamp.fromDate(end),
      location: event.venue,
      type: event.type,
      subjectCode: event.subjectCode,
      colorHex: colorConfig.colorHex,
      colorKey: colorConfig.colorKey,
      source: 'timetable_import',
      timetableId: null,
      recurrence: event.recurrence || undefined,
      createdAt: FieldValue.serverTimestamp(),
      updatedAt: FieldValue.serverTimestamp(),
    });

    events.push({
      title: event.title,
      type: event.type,
      subjectCode: event.subjectCode,
      startDateTime: start.toISOString(),
      endDateTime: end.toISOString(),
      venue: event.venue,
      colorKey: colorConfig.colorKey,
      recurrence: event.recurrence,
    });

    reminders.push(...buildReminders(docRef.id, event.title, event.type, start));
  }

  await logDecision({
    type: 'calendar_import',
    userId,
    allowed: true,
    eventsCreated: events.length,
    requestId: req.requestId || null,
  });

  const response: CalendarImportResponse = {
    eventsCreated: events.length,
    events,
    reminders,
  };

  res.json(response);
});

export default router;
