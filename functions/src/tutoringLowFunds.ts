export interface LowFundsNotificationPayload {
  type: "tutoring_low_funds";
  state: "low_funds" | "ended_insufficient_funds";
  reason: "reserve_refill_failed" | "protected_time_exhausted";
  notifyClients: true;
  protectedMinutesRemaining: number;
  consumedMinutes: number;
  refillAttemptCount: number;
  lowFundsAtIso: string | null;
  countdownEndsAtIso: string | null;
  countdownSecondsRemaining: number;
  roomTerminationRequired: boolean;
}

function deriveProtectionEndsAt(params: {
  sessionStartAt: Date | null;
  protectedMinutesPurchased: number;
  lowFundsAt?: Date | null;
  protectedMinutesRemaining?: number;
}): Date | null {
  if (params.sessionStartAt && params.protectedMinutesPurchased > 0) {
    return new Date(
      params.sessionStartAt.getTime() + (params.protectedMinutesPurchased * 60 * 1000)
    );
  }
  if (
    params.lowFundsAt &&
    typeof params.protectedMinutesRemaining === "number" &&
    params.protectedMinutesRemaining > 0
  ) {
    return new Date(
      params.lowFundsAt.getTime() + (params.protectedMinutesRemaining * 60 * 1000)
    );
  }
  return params.lowFundsAt ?? null;
}

export function computeLowFundsCountdown(params: {
  now: Date;
  sessionStartAt: Date | null;
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  lowFundsAt: Date | null;
}): {
  countdownEndsAt: Date | null;
  countdownSecondsRemaining: number;
} {
  const countdownEndsAt = deriveProtectionEndsAt(params);
  if (!countdownEndsAt) {
    return {
      countdownEndsAt: null,
      countdownSecondsRemaining: 0,
    };
  }
  return {
    countdownEndsAt,
    countdownSecondsRemaining: Math.max(
      0,
      Math.ceil((countdownEndsAt.getTime() - params.now.getTime()) / 1000)
    ),
  };
}

export function shouldForceEndForProtectionExhaustion(params: {
  now: Date;
  sessionStartAt: Date | null;
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  lowFundsAt: Date | null;
}): boolean {
  const countdown = computeLowFundsCountdown(params);
  return countdown.countdownSecondsRemaining <= 0;
}

export function buildLowFundsNotificationPayload(params: {
  now: Date;
  sessionStartAt: Date | null;
  protectedMinutesPurchased: number;
  protectedMinutesRemaining: number;
  consumedMinutes: number;
  refillAttemptCount: number;
  lowFundsAt: Date | null;
  state: "low_funds" | "ended_insufficient_funds";
  reason: "reserve_refill_failed" | "protected_time_exhausted";
}): LowFundsNotificationPayload {
  const countdown = computeLowFundsCountdown({
    now: params.now,
    sessionStartAt: params.sessionStartAt,
    protectedMinutesPurchased: params.protectedMinutesPurchased,
    protectedMinutesRemaining: params.protectedMinutesRemaining,
    lowFundsAt: params.lowFundsAt,
  });
  return {
    type: "tutoring_low_funds",
    state: params.state,
    reason: params.reason,
    notifyClients: true,
    protectedMinutesRemaining: params.protectedMinutesRemaining,
    consumedMinutes: params.consumedMinutes,
    refillAttemptCount: params.refillAttemptCount,
    lowFundsAtIso: params.lowFundsAt ? params.lowFundsAt.toISOString() : null,
    countdownEndsAtIso: countdown.countdownEndsAt ?
      countdown.countdownEndsAt.toISOString() :
      null,
    countdownSecondsRemaining: countdown.countdownSecondsRemaining,
    roomTerminationRequired: true,
  };
}
