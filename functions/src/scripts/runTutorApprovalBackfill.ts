import * as admin from "firebase-admin";

async function main(): Promise<void> {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }

  const tutorIdArg = process.argv.find((arg) => arg.startsWith("--tutorId="));
  const tutorId = tutorIdArg ? tutorIdArg.split("=")[1]?.trim() ?? "" : "";
  const dryRun = process.argv.includes("--dry-run");
  const {runTutorApprovalBackfillJob} = await import("../tutorApproval.js");
  const result = await runTutorApprovalBackfillJob({
    dryRun,
    tutorId,
    actorId: "script:tutor_approval_backfill",
  });

  console.log(JSON.stringify(result, null, 2));
}

void main().catch((error) => {
  console.error("Tutor approval backfill failed.");
  console.error(error);
  process.exitCode = 1;
});
