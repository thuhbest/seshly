export type AcademicGuardDecision =
  | { outcome: 'allow'; category: 'school' | 'unknown'; reason: 'academic_signals' | 'needs_model_review' }
  | { outcome: 'block'; category: 'non_school' | 'unknown'; reason: 'non_academic' | 'prompt_injection' | 'needs_academic_reframe'; message: string };

const ACADEMIC_PATTERNS = [
  /\b(math|mathematics|algebra|calculus|geometry|statistics)\b/i,
  /\b(physics|chemistry|biology|science|geography|history|economics)\b/i,
  /\b(assignment|exam|test|quiz|class|course|lecture|lesson|homework|syllabus|curriculum)\b/i,
  /\b(essay|thesis|research|paper|citation|references|study notes|notes|revision)\b/i,
  /\b(tutor|tutoring|school|university|college|campus|module|subject|topic)\b/i,
  /\b(explain|summari[sz]e|practice|flashcards?|solve|proof|formula|equation)\b/i,
];

const STRONG_ACADEMIC_PATTERNS = [
  /\b(calculus|algebra|geometry|statistics|physics|chemistry|biology|economics|history|geography)\b/i,
  /\b(assignment|exam|test|quiz|course|lecture|homework|research|essay|citation)\b/i,
  /\b(formula|equation|proof|flashcards?|revision|study notes|module|subject)\b/i,
];

const NON_ACADEMIC_PATTERNS = [
  /\b(dating|romance|boyfriend|girlfriend|flirting|sex)\b/i,
  /\b(movie|movies|netflix|anime|song|songs|music playlist|celebrity)\b/i,
  /\b(shopping|buy this|best phone|best laptop for gaming|fashion|outfit)\b/i,
  /\b(roleplay|pretend to be|fanfic|story game|joke|memes?)\b/i,
  /\b(travel itinerary|restaurant|recipe|fitness plan|workout routine)\b/i,
  /\b(life advice|relationship advice|general chat|just chat|bored)\b/i,
];

const BORDERLINE_PATTERNS = [
  /\b(help me\b)/i,
  /\bwhat do you think\b/i,
  /\btell me about\b/i,
  /\bcan you answer this\b/i,
];

const PROMPT_INJECTION_PATTERNS = [
  /\bignore (all|any|the) (previous|earlier) instructions\b/i,
  /\bdisregard (all|any|the) rules\b/i,
  /\bpretend (this|it) is for school\b/i,
  /\bact as\b/i,
  /\bsystem prompt\b/i,
];

export function buildSchoolOnlyMessage(borderline = false): string {
  if (borderline) {
    return 'Sesh is built for academic help only. Reframe this as a real school, study, assignment, or exam question. For general questions, try ChatGPT.';
  }
  return 'Sesh is built for academic help only. For general questions, try ChatGPT.';
}

export function evaluateAcademicGuard(text: string): AcademicGuardDecision {
  const normalized = text.trim();
  if (!normalized) {
    return {
      outcome: 'block',
      category: 'unknown',
      reason: 'needs_academic_reframe',
      message: buildSchoolOnlyMessage(true),
    };
  }

  const hasAcademicSignals = ACADEMIC_PATTERNS.some((pattern) => pattern.test(normalized));
  const hasStrongAcademicSignals = STRONG_ACADEMIC_PATTERNS.some((pattern) => pattern.test(normalized));
  const hasNonAcademicSignals = NON_ACADEMIC_PATTERNS.some((pattern) => pattern.test(normalized));
  const hasPromptInjectionSignals = PROMPT_INJECTION_PATTERNS.some((pattern) => pattern.test(normalized));
  const isBorderline = BORDERLINE_PATTERNS.some((pattern) => pattern.test(normalized));

  if (hasPromptInjectionSignals && !hasStrongAcademicSignals) {
    return {
      outcome: 'block',
      category: 'non_school',
      reason: 'prompt_injection',
      message: buildSchoolOnlyMessage(false),
    };
  }

  if (hasNonAcademicSignals && !hasAcademicSignals) {
    return {
      outcome: 'block',
      category: 'non_school',
      reason: 'non_academic',
      message: buildSchoolOnlyMessage(false),
    };
  }

  if (hasAcademicSignals) {
    return {
      outcome: 'allow',
      category: 'school',
      reason: 'academic_signals',
    };
  }

  if (isBorderline || normalized.length < 24) {
    return {
      outcome: 'block',
      category: 'unknown',
      reason: 'needs_academic_reframe',
      message: buildSchoolOnlyMessage(true),
    };
  }

  return {
    outcome: 'allow',
    category: 'unknown',
    reason: 'needs_model_review',
  };
}
