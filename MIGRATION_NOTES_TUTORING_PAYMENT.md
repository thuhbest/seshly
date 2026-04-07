# Tutoring Payment Migration Notes

## Retired From Live Tutoring Flow

- `functions/src/tutorPayments.ts`
  - Removed from `functions/src/index.ts`.
  - No live tutoring booking, authorization, settlement, or payout path exports from this file anymore.
  - Preserved only as legacy reference while existing data remains in Firestore.

- `functions/src/tutorPeachPayments.ts`
  - Removed from `functions/src/index.ts`.
  - Peach-specific tutoring callable exports are no longer the live entry point.
  - Preserved only as legacy/provider-reference material.

## New Live Tutoring Entry Points

- `createTutoringBooking`
  - Source: `functions/src/tutorBookings.ts`
  - Creates tutoring bookings and payment intents with pricing snapshots and tutoring-only metadata.

- `startTutoringPreauth`
  - Source: `functions/src/tutoringPayments.ts`
  - Initializes the tutoring authorization through the provider adapter.

- `respondToTutoringBooking`
  - Source: `functions/src/tutoringPayments.ts`
  - Replaces Flutter direct accept/decline writes.

- `startSession` / `endSession`
  - Source: `functions/src/tutorSessions.ts`
  - Remain the authoritative tutoring session lifecycle entry points.

- `billingTick`
  - Source: `functions/src/tutorBillingTick.ts`
  - Remains the authoritative minute-billing worker.

- `submitTutoringRating`
  - Source: `functions/src/tutorRatings.ts`
  - Replaces Flutter direct review writes.

- `saveMockTutoringPaymentMethod`
  - Source: `functions/src/tutoringPayments.ts`
  - Replaces client-side mock card field mutation for tutoring authorization readiness.

- `generateWeeklyTutorPayoutBatch`
  - Source: `functions/src/tutorPayouts.ts`
  - Draft-only weekly Monday batch scaffolding. No live transfer execution.

## Provider Layer

- New adapter boundary:
  - `functions/src/payments/tutoringPaymentProvider.ts`
  - `functions/src/payments/mockTutoringPaymentProvider.ts`

- Current live provider:
  - `MOCK_TUTORING`

- Pending provider work:
  - A single TODO seam remains in `getTutoringPaymentProvider()` for the future Paystack adapter.

## Preserved Behavior

- Tutoring still uses pay-per-minute billing.
- Student display pricing remains tutor rate plus 20%.
- Guest tutoring mode is still allowed for students.
- Tutors still require approved full accounts to accept bookings and enter payout flow.
- SeshCredits remains separate and untouched as a business system.
