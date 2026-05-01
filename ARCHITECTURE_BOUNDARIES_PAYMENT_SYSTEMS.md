# Payment System Boundaries

## 1. Tutoring Payments

Tutoring payments are a standalone server-authoritative system.

Authoritative backend files:

- `functions/src/tutorBookings.ts`
- `functions/src/tutoringPayments.ts`
- `functions/src/tutorSessions.ts`
- `functions/src/tutorBillingTick.ts`
- `functions/src/tutorPayouts.ts`
- `functions/src/payments/tutoringPaymentProvider.ts`
- `functions/src/payments/mockTutoringPaymentProvider.ts`

Rules:

- Tutoring uses pay-per-minute pricing.
- Student price is tutor rate multiplied by `1.20`.
- Tutoring sessions are not fixed 30/60 minute products.
- Protected prepaid time is enforced through tutoring authorizations and billing ticks.
- Guest tutoring mode is allowed only for students.
- Tutors must be approved full-account users.
- Tutor payouts come only from captured tutoring funds.
- Weekly tutor payout batching runs Monday 06:00 `Africa/Johannesburg` in draft/mock mode until provider execution is approved.

Firestore/record markers:

- `tutoringPaymentRail: "TUTORING"`
- `paymentSystem: "TUTORING"`
- `payoutFundingSource: "captured_tutoring_funds_only"`

## 2. SeshCredits

SeshCredits is a separate in-app utility system.

Scope:

- SeshFocus unlock passes
- audio note features
- recordings
- note/archive utility purchases

Rules:

- SeshCredits must not create or settle tutoring bookings.
- SeshCredits must not start or end tutoring sessions.
- SeshCredits must not feed tutor settlements or tutor payouts.
- Tutoring ratings and review eligibility must not depend on SeshCredits.

## 3. Separation Enforcement

- Flutter tutoring mutations now go through callable functions instead of direct Firestore writes.
- Firestore rules now block direct client writes to tutoring bookings, tutoring payment intents, tutoring reviews, and tutoring payment method collections.
- Tutoring payment artifacts now carry tutoring-specific markers so they are not mistaken for SeshCredits or other app utilities.
