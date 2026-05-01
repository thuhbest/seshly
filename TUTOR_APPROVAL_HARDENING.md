# Tutor Approval Hardening

## Scope

This patch makes tutor onboarding, tutor approval, tutoring eligibility, tutor search visibility, and payout readiness backend-authoritative without changing SeshCredits or starting live Paystack integration.

## Authoritative Tutor State

Backend-controlled tutor state now lives on `users/{tutorId}` and is mirrored onto `tutor_applications/{tutorId}`:

- `tutorApplicationStatus`: `draft | submitted | under_review | approved | rejected | suspended`
- `tutoringEligibilityStatus`: `ineligible | eligible | blocked`
- `payoutOnboardingStatus`: `not_started | pending | verified | blocked`
- `adminApproval`
- `adminApprovalAt`
- `adminApprovalBy`
- `rejectionReason`
- `suspensionReason`
- `tutoringSearchVisible`
- `tutoringSearchVisibilityReason`
- `tutoringApprovalVersion`
- `tutoringApprovalNormalizedAt`

`tutorStatus` remains only as a compatibility mirror for older tutor-facing code paths. It is derived from the authoritative fields and is no longer the source of truth.

## Backend Authority

Primary authority lives in:

- [functions/src/tutorApprovalState.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorApprovalState.ts)
- [functions/src/tutorApproval.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorApproval.ts)

Admin and tutor callables now include:

- `submitTutorApplication`
- `reviewTutorApplication`
- `approveTutorApplication`
- `rejectTutorApplication`
- `suspendTutor`
- `restoreTutor`
- `setTutorPayoutReadiness`
- `runTutorApprovalBackfill`

The backend now:

- rejects guest / instant-tutor accounts from tutor approval
- derives payout readiness from real `tutor_payout_accounts` records
- normalizes legacy tutor docs into the new status model
- updates tutor search visibility from authoritative eligibility only
- disables orphaned or stale `tutor_search_profiles` records
- keeps payout readiness aligned when payout-account docs change

## Admin UI

A minimal internal admin flow now exists:

- entry point: [lib/features/profile/view/profile_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/profile/view/profile_view.dart)
- list view: [lib/features/admin/view/tutor_review_admin_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/admin/view/tutor_review_admin_view.dart)
- detail view: [lib/features/admin/view/tutor_review_detail_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/admin/view/tutor_review_detail_view.dart)

The admin UI is restricted by token-based platform-admin checks and is wired to the backend callables only.

Admins can now:

- review submitted tutor applications
- open tutor detail
- approve
- reject
- suspend
- restore
- set payout readiness
- run tutor normalization/backfill from inside the app

## Client Authority Removed

[lib/features/profile/view/tutor_application_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/profile/view/tutor_application_view.dart) now submits tutor application data through backend callables and only reads backend state back.

Client writes are blocked for:

- tutor approval fields
- tutor eligibility fields
- tutor payout-readiness fields
- tutor search authority fields
- tutor application documents

These protections are enforced in [firestore.rules](/C:/Users/THUHBEST/Documents/my%20projects/seshly/firestore.rules).

## Search, Booking, Session, and Payout Enforcement

Tutoring operations now require backend-authoritative tutor approval:

- bookings: [functions/src/tutorBookings.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorBookings.ts)
- booking acceptance / payment orchestration: [functions/src/tutoringPayments.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutoringPayments.ts)
- session start: [functions/src/tutorSessions.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorSessions.ts)
- payouts and Monday payout batches: [functions/src/tutorPayouts.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorPayouts.ts)
- search query source: [lib/services/tutor_identity_service.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/services/tutor_identity_service.dart)

Effects:

- unapproved tutors cannot appear in tutor search
- suspended or blocked tutors cannot appear in tutor search
- unapproved tutors cannot accept tutoring bookings
- unapproved tutors cannot start tutoring sessions
- only approved, payout-ready tutors can request payouts
- Monday payout batches skip blocked or ineligible tutors automatically

## Migration and Backfill

Normalization now has both backend and script entry points:

- callable: `runTutorApprovalBackfill`
- script: [functions/src/scripts/runTutorApprovalBackfill.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/scripts/runTutorApprovalBackfill.ts)
- npm commands:
  - `npm run backfill:tutor-approval`
  - `npm run backfill:tutor-approval:dry-run`

Normalization is idempotent and now:

- creates or updates missing tutor authority fields
- resolves payout readiness for approved tutors from payout-account completeness
- marks approved tutors with complete active payout accounts as `verified`
- marks approved tutors with missing payout fields as `pending`
- marks guest tutor attempts as ineligible and rejected
- rewrites stale `tutor_search_profiles` from backend authority
- disables orphaned `tutor_search_profiles`

## Indexes and Rules

Added:

- tutor search composite index on `tutoringSearchVisible + subjects + searchScore`
- tutor application status index on `tutorApplicationStatus + updatedAt`
- search-profile read rule for signed-in users
- stronger rule checks so legacy tutor approval cannot pass for `instant_tutor` accounts

## Verification

Local verification completed:

- `npm run build` in `functions`
- `flutter analyze --no-pub`

See [ZERO_BLOCKER_VERIFICATION_TUTOR_APPROVAL.md](/C:/Users/THUHBEST/Documents/my%20projects/seshly/ZERO_BLOCKER_VERIFICATION_TUTOR_APPROVAL.md) for the full zero-blocker checklist.
