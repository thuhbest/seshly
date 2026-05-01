# Tutoring Payment Patch Plan

## Scope

- Goal: finish the tutoring payment system without live Paystack APIs.
- Constraint: patch the existing tutoring flow only. Do not rewrite the app. Do not touch SeshCredits.
- Current architecture stance in the repo: live tutoring flow is centered on callable/session-control backend code, with a mock-provider path and schema-normalization scaffolding partially present.

## Audit Inventory

### Backend files and functions

| Domain | Current live files / functions | Legacy or support files | Notes |
| --- | --- | --- | --- |
| Bookings | `functions/src/tutorBookings.ts` -> `createTutoringBooking`, `createBooking` | `functions/src/tutorCalendarSync.ts` -> `ontutorrequestcalendarupdated` | Live booking source of truth writes `tutor_requests` and `session_payment_intents`. |
| Sessions | `functions/src/tutorSessions.ts` -> `startSession`, `endSession`, `prepareSessionRuntime`, `attemptAutoStart` | `functions/src/sessionAutoStart.ts`, `functions/src/tutorRoomControl.ts` | Runtime session state lives in `tutoring_sessions`. |
| Payment sessions / authorizations | `functions/src/tutoringPayments.ts` -> `saveMockTutoringPaymentMethod`, `startTutoringPreauth`, `respondToTutoringBooking` | `functions/src/tutorPeachPayments.ts`, `functions/src/tutorPayments.ts`, `functions/src/payments/tutoringPaymentProvider.ts`, `functions/src/payments/mockTutoringPaymentProvider.ts` | Live path is mock-provider based. Peach and legacy payment flows still exist in repo as reference code. |
| Captures / minute billing | `functions/src/tutorBillingTick.ts` -> `billingTick` | `functions/src/tutorSessions.ts` capture/reversal helpers | Captures write `payment_captures`. Reversals write `payment_reversals`. |
| Settlements | `functions/src/tutorSessions.ts` -> settlement finalization | `functions/src/tutorTrust.ts` outcome/review trust signals | Settlements write `tutor_session_settlements` and `tutor_session_outcomes`. |
| Payouts | `functions/src/tutorPayouts.ts` -> `generateWeeklyTutorPayoutBatch`, `requestTutorPayout`, `approveTutorPayout`, `rejectTutorPayout`, `markTutorPayoutProcessing`, `markTutorPayoutPaid`, `markTutorPayoutFailed` | `functions/src/tutorPayoutModels.ts` | Weekly Monday draft-batch scheduler exists. |
| Tutor onboarding / approval | `functions/src/tutorApproval.ts` -> `submitTutorApplication`, `reviewTutorApplication`, `approveTutorApplication`, `rejectTutorApplication`, `suspendTutor`, `restoreTutor`, `setTutorPayoutReadiness`, `runTutorApprovalBackfill` | `functions/src/tutorApprovalState.ts`, `functions/src/scripts/runTutorApprovalBackfill.ts` | Tutor approval is server-authoritative. |
| Schema normalization | `functions/src/tutoringFirestoreSchema.ts`, `functions/src/tutoringPaymentSchemaBackfill.ts` -> `runTutoringPaymentSchemaBackfill` | `functions/src/scripts/runTutoringPaymentSchemaBackfill.ts` | Present, but not yet fully threaded through every tutoring write path. |
| Tutor discovery / search | `functions/src/tutorApproval.ts` search-profile sync | `functions/src/tutorSearchRanking.ts` | Live tutor visibility depends on approval snapshot and `tutor_search_profiles`. |
| Ratings | `functions/src/tutorRatings.ts` -> `submitTutoringRating` | `functions/src/tutorTrust.ts` | Ratings write `tutor_session_reviews`. |

### Flutter services and screens

| Domain | Flutter files / screens |
| --- | --- |
| Bookings / tutor search | `lib/services/tutor_request_service.dart`, `lib/services/tutoring_backend_service.dart`, `lib/features/tutors/view/find_tutor_view.dart`, `lib/features/profile/view/tutor_stats_view.dart`, `lib/features/profile/view/instant_tutor_mode_account_view.dart` |
| Payment method setup | `lib/services/billing_profile_service.dart`, `lib/features/tutors/view/recharge_view.dart` |
| Session / lifecycle entry | `lib/services/tutoring_backend_service.dart` exposes `startSession` and `endSession`, but no dedicated tutoring session UI is wired to it yet |
| Ratings | `lib/services/tutor_review_service.dart` |
| Tutor onboarding | `lib/features/profile/view/tutor_application_view.dart`, `lib/services/tutor_identity_service.dart`, `lib/access/tutor_access_policy.dart` |
| Admin tutor review | `lib/features/admin/view/tutor_review_admin_view.dart`, `lib/features/admin/view/tutor_review_detail_view.dart`, `lib/features/profile/view/profile_view.dart`, `lib/services/platform_admin_service.dart` |
| Guest tutoring mode | `lib/services/auth_service.dart`, `lib/features/profile/view/instant_tutor_mode_account_view.dart`, `lib/access/app_access.dart`, `lib/access/app_identity.dart`, `lib/features/login/view/login_page_view.dart`, `lib/features/home/view/main_wrapper.dart` |

### Firestore collections and subcollections used by tutoring

- Bookings: `tutor_requests`, `booking_idempotency`
- Payment sessions: `session_payment_intents`
- Sessions: `tutoring_sessions`, `tutoring_sessions/{sessionId}/participants`, `tutoring_sessions/{sessionId}/billing_ticks`
- Payment internals: `payment_authorizations`, `payment_captures`, `payment_reversals`
- Settlements: `tutor_session_settlements`, `tutor_session_outcomes`
- Ratings: `tutor_session_reviews`
- Payouts: `tutor_balances`, `tutor_payout_accounts`, `tutor_payout_batches`, `tutor_payout_batches/{batchId}/items`, `tutor_payouts`, `tutor_payouts/{payoutId}/allocations`, `tutor_payout_events`
- Tutor onboarding / search: `tutor_applications`, `tutor_search_profiles`, `tutor_organizations`, `tutor_organizations/{orgId}/members`
- Guest tutoring support: `users/{uid}/temporary_payment_methods`, `users/{uid}/payment_methods`, `guest_tutoring_customers`
- Schema placeholder / partial support: `tutor_payables`, `disputes`

### Exported live tutoring functions from `functions/src/index.ts`

- `createTutoringBooking`
- `submitTutoringRating`
- `startSession`
- `endSession`
- `billingTick`
- `submitTutorApplication`
- `reviewTutorApplication`
- `approveTutorApplication`
- `rejectTutorApplication`
- `suspendTutor`
- `restoreTutor`
- `setTutorPayoutReadiness`
- `runTutorApprovalBackfill`
- `runTutoringPaymentSchemaBackfill`
- `generateWeeklyTutorPayoutBatch`
- `requestTutorPayout`
- `approveTutorPayout`
- `rejectTutorPayout`
- `markTutorPayoutProcessing`
- `markTutorPayoutPaid`
- `markTutorPayoutFailed`
- `saveMockTutoringPaymentMethod`
- `startTutoringPreauth`
- `respondToTutoringBooking`

### Legacy or dormant tutoring files still present in repo

- `functions/src/tutorPayments.ts`
- `functions/src/tutorPeachPayments.ts`
- `functions/src/sessionAutoStart.ts`
- `functions/src/tutorSearchRanking.ts`

## Gap Analysis Against Target System

### 1. Pay-per-minute server-authoritative billing

Current state:

- Backend-authoritative booking, preauth, session start/end, billing tick, settlement, and payout scaffolding exist.
- Flutter booking acceptance and payment initiation now call backend callables.
- Legacy tutoring payment files still exist in the repo, but the live exported path is the newer callable-based flow.

Remaining gap:

- The dedicated tutoring session client is not wired to `startSession`, `endSession`, `tutoring_sessions`, or minute-billing state.
- The physical Firestore collection names are still legacy (`tutor_requests`, `session_payment_intents`, `tutoring_sessions`) rather than the logical target names (`bookings`, `payment_sessions`, `sessions`).
- Schema normalization is only partially connected; payout and rating docs are not yet fully normalized end-to-end.

### 2. Student sees `tutorRate * 1.20`

Current state:

- Backend booking pricing still calculates `studentRatePerMinZar = tutorRatePerMinZar * 1.2`.
- Flutter tutor pricing still presents the markup.

Remaining gap:

- Canonical pricing fields are still duplicated across docs under mixed names (`pricing`, `pricingSnapshot`, `totalRatePerMinute`, `displayRate`).
- Not every tutoring write path persists the same normalized pricing snapshot.

### 3. Sessions can end anytime, not fixed 30/60 only

Current state:

- Backend settlement logic is runtime-based and pay-per-minute.
- `billingTick` and `endSession` support open-ended runtime.

Remaining gap:

- The client still does not expose a true open-ended live tutoring session screen.
- Some Flutter request/response models still carry fixed-style `startAt/endAt` assumptions for display convenience.

### 4. No free learning beyond protected prepaid time

Current state:

- `billingTick` captures minute by minute, requests buffer top-ups, marks low funds, and force-ends the room when prepaid protection expires.

Remaining gap:

- No student/tutor UI subscribes to low-funds state or protected-minute depletion.
- Session state is enforced on backend, but not surfaced in a tutoring-specific live UX.

### 5. Guest tutoring mode allowed for students without full accounts

Current state:

- Guest tutoring mode exists in auth/access logic.
- Temporary payment methods exist.
- `guest_tutoring_customers` schema/backfill scaffolding is present.

Remaining gap:

- Guest-customer normalization is only partially wired. It is not yet a complete, stable source for all guest tutoring history.
- Firestore rules and indexes do not yet cover the new guest tutoring schema surfaces.

### 6. Tutors must have full accounts

Current state:

- Tutor onboarding and approval are backend-authoritative.
- Guest accounts are blocked from tutor approval and tutoring eligibility.

Remaining gap:

- None at the eligibility model level. The remaining work is schema normalization around tutor payout profile and tutoring payment docs.

### 7. Tutors are paid weekly every Monday

Current state:

- `generateWeeklyTutorPayoutBatch` exists and is scheduled for Monday 06:00 `Africa/Johannesburg`.

Remaining gap:

- Batch generation is still draft/mock only.
- Batch, payout, and payable schema fields are not fully normalized across all write paths.

### 8. Payouts come only from captured funds

Current state:

- Settlement math derives tutor earnings from captured tutoring funds.
- Settlement docs already record captured totals and payout-ledger values.
- Weekly payout batches read only settlement-derived tutor amounts.

Remaining gap:

- `tutor_payables` is not yet the consistently maintained canonical derived payable collection.
- Dispute scaffolding exists only as a schema placeholder, not a full lifecycle.

## Missing Backend Pieces

### P0

- Finish one single tutoring schema normalization pass across:
  - `tutorPayouts.ts`
  - `tutorRatings.ts`
  - payout-batch draft items
  - `firestore.rules`
  - `firestore.indexes.json`
- Fully connect `tutor_payables` so it updates when:
  - settlements are created
  - payout allocations are reserved
  - payout allocations are released
  - payouts are marked paid
  - Monday draft batches are generated
- Add explicit dispute placeholder writes only when settlement funds are held, so `disputes` is not just a dormant schema target.

### P1

- Normalize the remaining tutoring docs to a single schema vocabulary:
  - common schema metadata
  - canonical `pricingSnapshot`
  - `authorizationBufferMinutes`
  - payout week/date keys
  - guest tutoring customer linkage
- Export or consciously retire dormant tutoring files:
  - `tutorPayments.ts`
  - `tutorPeachPayments.ts`
  - `sessionAutoStart.ts`
  - `tutorSearchRanking.ts`

## Missing Firestore Fields

### Common tutoring doc metadata still not universal

- `tutoringSchemaVersion`
- `tutoringSchemaDomain`
- `tutoringSchemaCollection`
- `tutoringSchemaPhysicalCollection`
- `tutoringSchemaNormalizedAt`

### `tutor_requests`

- `sessionOpenEnded`
- `protectedPrepaidMinutesOnly`
- `guestTutoringCustomerId`
- consistent `pricingSnapshot`
- consistent `authorizationBufferMinutes`

### `session_payment_intents`

- `latestAuthorizationId`
- `latestCaptureId`
- `latestReversalId`
- `authorizationBufferMinutes`
- consistent `pricingSnapshot`
- `guestTutoringCustomerId`

### `tutoring_sessions`

- consistent `pricingSnapshot`
- `authorizationBufferMinutes`
- `lowFundsGraceEndsAt`
- consistent schema metadata on every write path

### `payment_authorizations`

- `paymentAuthorizationId`
- `sessionId`
- `paymentSessionId`
- `authorizationKind`
- `authorizationStatus`
- `remainingAuthorizedAmountZar`

### `payment_captures`

- `captureRecordId`
- `paymentAuthorizationId`
- `paymentSessionId`
- `captureStatus`
- `capturedAmountZar`

### `tutor_session_settlements`

- `settlementRecordId`
- `tutorPayableId`
- `payoutWeekKey`
- `scheduledPayoutDateKey`
- `scheduledPayoutLocalTime`

### `tutor_payables`

- `payableId`
- `payableStatus`
- `grossTutorEarningZar`
- `availableAmountZar`
- `reservedAmountZar`
- `paidAmountZar`
- `blockedAmountZar`
- `lastPayoutBatchId`
- `lastPayoutRecordId`
- `disputeId`

### `tutor_payout_accounts`

- `payoutProfileId`
- `payoutProfileStatus`
- provider-agnostic onboarding markers aligned with tutoring payouts

### `tutor_payout_batches`

- `payoutBatchId`
- `payoutWeekKey`
- `scheduledPayoutDateKey`
- `scheduledPayoutLocalTime`
- `payoutBatchStatus`

### `tutor_payouts`

- `payoutRecordId`
- `payoutProfileId`
- `payoutWeekKey`
- `payoutDateKey`
- `payoutRecordStatus`

### `guest_tutoring_customers`

- `guestTutoringCustomerId`
- `temporaryPaymentMethodId`
- `temporaryPaymentRegistrationId`
- `temporaryPaymentProviderReference`
- `temporaryPaymentSetupStatus`
- `tutoringBookingCount`
- `lastBookingId`
- `lastBookingAt`

### `disputes`

- `disputeId`
- `settlementId`
- `sessionId`
- `paymentSessionId`
- `heldAmountZar`
- `status`

### `tutor_session_reviews`

- `ratingId`
- `sessionId`
- `paymentSessionId`
- `ratingStatus`

## Missing UI / Backend Dependencies

- No dedicated tutoring session screen is wired to backend session/payment state yet.
- No client UI consumes `tutoring_sessions` or `billing_ticks` for low-funds / protected-time feedback.
- No payout account management UI exists beyond raw Firestore-backed account docs surfaced in admin review.
- No tutor payout request/history UI exists for tutors.
- `firestore.rules` does not yet cover all new tutoring schema collections:
  - `payment_authorizations`
  - `payment_captures`
  - `guest_tutoring_customers`
  - `tutor_payables`
  - `disputes`
  - `tutor_payout_batches`
- `firestore.indexes.json` still lacks the required tutoring composite indexes for bookings, active sessions, authorizations, payables, payouts, and guest bookings.

## Exact Files To Modify

### Backend

- `functions/src/tutorPayouts.ts`
- `functions/src/tutorRatings.ts`
- `functions/src/tutoringPayments.ts`
- `functions/src/tutorBillingTick.ts`
- `functions/src/tutorSessions.ts`
- `functions/src/tutoringFirestoreSchema.ts`
- `functions/src/tutoringPaymentSchemaBackfill.ts`
- `functions/src/index.ts`

### Security / schema

- `firestore.rules`
- `firestore.indexes.json`

### Flutter

- `lib/services/tutoring_backend_service.dart`
- `lib/services/tutor_request_service.dart`
- `lib/services/tutor_review_service.dart`
- `lib/services/billing_profile_service.dart`
- `lib/services/tutor_identity_service.dart`
- `lib/features/tutors/view/find_tutor_view.dart`
- `lib/features/tutors/view/recharge_view.dart`
- `lib/features/profile/view/tutor_stats_view.dart`
- dedicated tutoring session UI file(s) once implementation starts

### Docs to create or update

- `TUTORING_PAYMENT_PATCH_PLAN.md`
- `MIGRATION_NOTES_TUTORING_PAYMENT.md`
- tutoring Firestore schema documentation file for canonical logical-to-physical mapping and example documents

## Recommended Patch Order

1. Finish payout/payable/rating schema normalization on the live tutoring path.
2. Add Firestore rules for new tutoring schema collections.
3. Add required composite indexes for tutoring bookings, active sessions, authorizations, payables, payouts, and guest bookings.
4. Document the final tutoring Firestore schema with example JSON docs and logical-to-physical collection mapping.
5. Only after that, start the dedicated tutoring session client and any later Paystack adapter work.

## Non-Goals For This Patch Plan

- Do not integrate live Paystack APIs.
- Do not rewrite the existing tutoring collections to literal top-level `bookings` / `sessions` collection names.
- Do not touch SeshCredits.
- Do not build the dedicated tutoring session screen in this planning step.
