# Zero-Blocker Verification: Tutor Approval

## 1. Admin Review UI Path / Route

- App path: `Profile` -> `Tutor Review Admin`
- Entry point: [lib/features/profile/view/profile_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/profile/view/profile_view.dart)
- Admin list: [lib/features/admin/view/tutor_review_admin_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/admin/view/tutor_review_admin_view.dart)
- Admin detail: [lib/features/admin/view/tutor_review_detail_view.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/features/admin/view/tutor_review_detail_view.dart)
- Access gate: [lib/services/platform_admin_service.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/services/platform_admin_service.dart)

## 2. Backend Callables Used

- `submitTutorApplication`
- `reviewTutorApplication`
- `approveTutorApplication`
- `rejectTutorApplication`
- `suspendTutor`
- `restoreTutor`
- `setTutorPayoutReadiness`
- `runTutorApprovalBackfill`

Implementation source:

- [functions/src/tutorApproval.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorApproval.ts)
- [functions/src/index.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/index.ts)
- Flutter callable client: [lib/services/tutoring_backend_service.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/services/tutoring_backend_service.dart)

## 3. Migration Scripts Created

- One-shot script: [functions/src/scripts/runTutorApprovalBackfill.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/scripts/runTutorApprovalBackfill.ts)
- Callable entry for safe in-app execution: `runTutorApprovalBackfill`
- Live sync triggers:
  - `ontutorapprovaluserwritten`
  - `ontutorpayoutaccountwritten`

## 4. Search Visibility Rules

- Tutor discovery reads [lib/services/tutor_identity_service.dart](/C:/Users/THUHBEST/Documents/my%20projects/seshly/lib/services/tutor_identity_service.dart) and now filters on `tutoringSearchVisible == true`
- Search profile source-of-truth fields are written only by backend normalization in [functions/src/tutorApproval.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorApproval.ts)
- Search profile reads are allowed to signed-in users; client writes are blocked in [firestore.rules](/C:/Users/THUHBEST/Documents/my%20projects/seshly/firestore.rules)
- Orphan or stale `tutor_search_profiles` docs are disabled during normalization/backfill

## 5. Payout Readiness Rules

- `payoutOnboardingStatus` is now server-derived from authoritative tutor approval plus `tutor_payout_accounts`
- `verified` requires an approved, eligible, full-account tutor with a complete active payout account
- `pending` is assigned when a tutor is approved but payout data is missing or incomplete
- `blocked` is assigned when payout-block flags or tutor suspension/blocking is present
- Weekly payout batching in [functions/src/tutorPayouts.ts](/C:/Users/THUHBEST/Documents/my%20projects/seshly/functions/src/tutorPayouts.ts) only includes payout-ready tutors

## 6. Exact Checks Proving Prompt-2 Readiness

- Admin review UI exists and is reachable in-app.
- Admin actions approve, reject, suspend, restore, payout readiness update, and normalization are callable from the UI.
- Tutor application approval is backend-only; the client can no longer self-approve.
- Guest / `instant_tutor` accounts are rejected from tutor approval and cannot pass legacy approval fallback rules.
- Tutor search visibility is backend-authored through `tutoringSearchVisible`.
- Booking acceptance and session start already require approved, eligible tutors.
- Payout requests and weekly Monday payout drafts already require payout-ready tutors.
- Existing tutor docs, payout statuses, and search profiles now have an idempotent normalization path.
- Live sync triggers keep search visibility and payout readiness aligned after user or payout-account changes.
- Verification passed:
  - `npm run build` in `functions`
  - `flutter analyze --no-pub`
