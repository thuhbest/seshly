import {
  HttpsError,
  beforeEmailSent,
  beforeUserCreated,
  beforeUserSignedIn,
} from "firebase-functions/v2/identity";

import {
  enforceRateLimitForAuthEvent,
  recordMonitoringEvent,
  recordPrivacySafeAnalyticsEvent,
} from "./security";

const REGION = "europe-west1";

function normalizeEmail(value: unknown): string {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

async function recordAuthSignal(params: {
  action: string;
  actorUid?: string;
  severity: "info" | "warning" | "critical";
  message: string;
  metadata?: Record<string, unknown>;
}): Promise<void> {
  await recordMonitoringEvent({
    action: params.action,
    severity: params.severity,
    actorUid: params.actorUid,
    message: params.message,
    metadata: params.metadata,
  });
}

export const beforeauthusercreated = beforeUserCreated(
  {region: REGION},
  async (event) => {
    const email = normalizeEmail(event.data?.email ?? event.additionalUserInfo?.email);
    await enforceRateLimitForAuthEvent({
      action: "auth.signup",
      ipAddress: event.ipAddress,
      subject: email,
      profile: "auth",
    });

    const recaptchaScore = Number(event.additionalUserInfo?.recaptchaScore ?? 1);
    if (Number.isFinite(recaptchaScore) && recaptchaScore < 0.2) {
      await recordAuthSignal({
        action: "auth.signup",
        severity: "warning",
        message: "Low recaptcha score on signup",
        metadata: {recaptchaScore},
      });
      throw new HttpsError("resource-exhausted", "Too many attempts. Please try again later.");
    }

    await recordPrivacySafeAnalyticsEvent({
      eventType: "signup_flow",
      action: "auth.signup",
      actorType: "unauthenticated",
      status: "ok",
      metadata: {
        hasEmail: email.length > 0,
        providerId: event.credential?.providerId ?? "",
      },
    });
  }
);

export const beforeauthusersignedin = beforeUserSignedIn(
  {region: REGION},
  async (event) => {
    const email = normalizeEmail(event.data?.email ?? event.additionalUserInfo?.email);
    await enforceRateLimitForAuthEvent({
      action: "auth.signin",
      ipAddress: event.ipAddress,
      subject: email || event.data?.uid,
      profile: "auth",
    });

    const signInMethod = event.credential?.signInMethod ?? "";
    const recaptchaScore = Number(event.additionalUserInfo?.recaptchaScore ?? 1);
    if (Number.isFinite(recaptchaScore) && recaptchaScore < 0.15) {
      await recordAuthSignal({
        action: "auth.signin",
        severity: "warning",
        actorUid: event.data?.uid,
        message: "Low recaptcha score on sign-in",
        metadata: {recaptchaScore, signInMethod},
      });
      throw new HttpsError("resource-exhausted", "Too many attempts. Please try again later.");
    }

    if (signInMethod && !["password", "anonymous", "google.com"].includes(signInMethod)) {
      await recordAuthSignal({
        action: "auth.signin",
        severity: "info",
        actorUid: event.data?.uid,
        message: "Observed non-standard sign-in method",
        metadata: {signInMethod},
      });
    }

    await recordPrivacySafeAnalyticsEvent({
      eventType: "login_flow",
      action: "auth.signin",
      actorUid: event.data?.uid,
      actorType: event.data?.uid ? "user" : "unauthenticated",
      status: "ok",
      metadata: {
        providerId: event.credential?.providerId ?? "",
        signInMethod,
      },
    });
  }
);

export const beforeauthemailsent = beforeEmailSent(
  {region: REGION},
  async (event) => {
    if (event.emailType !== "PASSWORD_RESET") {
      return;
    }

    const email = normalizeEmail(event.additionalUserInfo?.email ?? event.data?.email);
    await enforceRateLimitForAuthEvent({
      action: "auth.password_reset",
      ipAddress: event.ipAddress,
      subject: email,
      profile: "auth",
    });

    await recordPrivacySafeAnalyticsEvent({
      eventType: "password_reset",
      action: "auth.password_reset",
      actorType: "unauthenticated",
      status: "ok",
      metadata: {hasEmail: email.length > 0},
    });
  }
);
