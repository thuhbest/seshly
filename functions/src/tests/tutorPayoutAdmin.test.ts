import test from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";

if (admin.apps.length === 0) {
  admin.initializeApp();
}

import {
  buildAdminPayoutCsv,
  nextOrSameMondayDateKey,
} from "../tutorPayoutAdmin.js";

test("nextOrSameMondayDateKey resolves the payout week in Africa/Johannesburg", () => {
  assert.equal(
    nextOrSameMondayDateKey(new Date("2026-04-01T08:00:00.000Z")),
    "2026-04-06",
  );
  assert.equal(
    nextOrSameMondayDateKey(new Date("2026-04-06T02:00:00.000Z")),
    "2026-04-06",
  );
});

test("buildAdminPayoutCsv escapes commas, quotes, and nulls", () => {
  const csv = buildAdminPayoutCsv(
    ["name", "note", "amount"],
    [{
      name: "Tutor, A",
      note: "Needs \"retry\" batch",
      amount: null,
    }],
  );

  assert.equal(
    csv,
    'name,note,amount\n"Tutor, A","Needs ""retry"" batch",',
  );
});
