export type ModerationSeverity =
  | "allow"
  | "allow_with_flag"
  | "block"
  | "rate_limit_user";

export interface ModerationDecision {
  severity: ModerationSeverity;
  reasons: string[];
  sanitizedText: string;
  normalizedText: string;
  linkCount: number;
}

const MAX_COLLAPSED_WHITESPACE = /\s+/g;
const ZERO_WIDTH_CHARS = /[\u200B-\u200D\uFEFF]/g;
const SCRIPT_TAGS = /<script\b[^<]*(?:(?!<\/script>)<[^<]*)*<\/script>/gi;
const HTML_TAGS = /<\/?[^>]+>/g;
const JAVASCRIPT_URI = /javascript:/gi;
const DATA_URI = /data:text\/html/gi;
const ON_EVENT_ATTR = /\bon[a-z]+\s*=/gi;
const LINK_REGEX =
  /\b(?:https?:\/\/|www\.|hxxps?:\/\/|hxxps?:\/\/|[a-z0-9.-]+\s*(?:\[dot\]|\(dot\)|\{dot\}| dot )\s*[a-z]{2,})(?:[^\s<]*)/gi;
const ACADEMIC_CONTEXT_REGEX =
  /\b(assignment|essay|exam|research|study|case study|history|literature|novel|quote|quotation|analysis|academic|biology|chemistry|reproduction|the term|definition|discuss|review)\b/i;
const DIRECT_TARGET_REGEX = /\b(you|your|u|ur|him|her|them)\b/i;

const HATE_PATTERNS = [
  /\b(kike|nigg(?:a|er)|fagg(?:ot)?|trann(?:y|ie)|spic|chink|raghead)\b/i,
];

const HARASSMENT_PATTERNS = [
  /\b(kill yourself|kys|go die|drop dead|worthless idiot|stupid bitch|piece of shit)\b/i,
  /\b(i will (?:hurt|beat|find|stab|shoot) you)\b/i,
];

const EXPLOITATION_PATTERNS = [
  /\b(child porn|csam|sexual (?:abuse|exploitation)|minor\s+(?:nude|sex|explicit)|underage\s+(?:nude|sex|explicit))\b/i,
  /\b(send nudes?|explicit pics?|sex tape)\b/i,
];

const SCAM_PATTERNS = [
  /\b(send (?:your )?(?:card|bank|otp|pin|password|login) details)\b/i,
  /\b(crypto giveaway|investment guarantee|double your money|guaranteed returns)\b/i,
  /\b(pay now outside|telegram me for answers|whatsapp me for leaks|dm me for exam leaks)\b/i,
];

const FLAG_PATTERNS = [
  /\b(whatsapp|telegram|cash app|cashapp|western union|gift card)\b/i,
  /\b(buy essays?|sell papers?|answer key|exam leak|proxy exam)\b/i,
];

function collapseWhitespace(value: string): string {
  return value.replace(MAX_COLLAPSED_WHITESPACE, " ").trim();
}

export function sanitizeTextContent(value: unknown, maxLength = 4000): string {
  const raw = typeof value === "string" ? value : "";
  const withoutScripts = raw
    .normalize("NFKC")
    .replace(ZERO_WIDTH_CHARS, "")
    .replace(SCRIPT_TAGS, " ")
    .replace(HTML_TAGS, " ")
    .replace(JAVASCRIPT_URI, "")
    .replace(DATA_URI, "")
    .replace(ON_EVENT_ATTR, "");

  return collapseWhitespace(withoutScripts).slice(0, maxLength);
}

export function normalizeLinksForModeration(value: string): string {
  return value
    .replace(/hxxps?:\/\//gi, "https://")
    .replace(/\[dot\]|\(dot\)|\{dot\}| dot /gi, ".")
    .replace(/\s*@\s*/g, "@");
}

export function normalizeTextFingerprint(value: string): string {
  return collapseWhitespace(normalizeLinksForModeration(value).toLowerCase());
}

function countLinks(value: string): number {
  const matches = value.match(LINK_REGEX);
  return matches?.length ?? 0;
}

function repeatedTokenFlood(value: string): boolean {
  const tokens = value
    .split(" ")
    .map((token) => token.trim())
    .filter((token) => token.length > 0);
  if (tokens.length < 6) return false;

  const counts = new Map<string, number>();
  for (const token of tokens) {
    const normalized = token.toLowerCase();
    counts.set(normalized, (counts.get(normalized) ?? 0) + 1);
    if ((counts.get(normalized) ?? 0) >= 6) {
      return true;
    }
  }
  return /(.)\1{11,}/.test(value);
}

function isAcademicContext(value: string): boolean {
  return ACADEMIC_CONTEXT_REGEX.test(value);
}

function escalateSeverity(
  current: ModerationSeverity,
  next: ModerationSeverity
): ModerationSeverity {
  const priority: Record<ModerationSeverity, number> = {
    allow: 0,
    allow_with_flag: 1,
    block: 2,
    rate_limit_user: 3,
  };
  return priority[next] > priority[current] ? next : current;
}

export function evaluateModeration(
  value: unknown,
  options?: {maxLength?: number}
): ModerationDecision {
  const sanitizedText = sanitizeTextContent(value, options?.maxLength ?? 4000);
  const normalizedText = normalizeTextFingerprint(sanitizedText);
  const reasons: string[] = [];
  let severity: ModerationSeverity = "allow";
  const linkCount = countLinks(normalizedText);
  const academicContext = isAcademicContext(normalizedText);

  if (!normalizedText) {
    return {
      severity,
      reasons,
      sanitizedText,
      normalizedText,
      linkCount,
    };
  }

  if (linkCount >= 3 || repeatedTokenFlood(normalizedText)) {
    severity = "rate_limit_user";
    reasons.push("spam_flood");
  }

  for (const pattern of HATE_PATTERNS) {
    if (pattern.test(normalizedText)) {
      severity = escalateSeverity(severity, academicContext ? "allow_with_flag" : "block");
      reasons.push("hate_speech");
      break;
    }
  }

  for (const pattern of HARASSMENT_PATTERNS) {
    if (pattern.test(normalizedText)) {
      const targeted = DIRECT_TARGET_REGEX.test(normalizedText);
      severity = escalateSeverity(
        severity,
        academicContext && !targeted ? "allow_with_flag" : "block"
      );
      reasons.push("harassment_threat");
      break;
    }
  }

  for (const pattern of EXPLOITATION_PATTERNS) {
    if (pattern.test(normalizedText)) {
      severity = escalateSeverity(severity, academicContext ? "allow_with_flag" : "block");
      reasons.push("sexual_exploitation");
      break;
    }
  }

  for (const pattern of SCAM_PATTERNS) {
    if (pattern.test(normalizedText)) {
      severity = escalateSeverity(severity, "block");
      reasons.push("scam_risk");
      break;
    }
  }

  for (const pattern of FLAG_PATTERNS) {
    if (pattern.test(normalizedText)) {
      severity = escalateSeverity(severity, "allow_with_flag");
      reasons.push("policy_flag");
      break;
    }
  }

  return {
    severity,
    reasons,
    sanitizedText,
    normalizedText,
    linkCount,
  };
}
