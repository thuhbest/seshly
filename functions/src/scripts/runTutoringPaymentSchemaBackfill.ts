import * as admin from "firebase-admin";

async function main(): Promise<void> {
  if (admin.apps.length === 0) {
    admin.initializeApp();
  }

  const dryRun = process.argv.includes("--dry-run");
  const {runTutoringPaymentSchemaBackfillJob} = await import(
    "../tutoringPaymentSchemaBackfill.js"
  );
  const result = await runTutoringPaymentSchemaBackfillJob({
    dryRun,
  });

  console.log(JSON.stringify(result, null, 2));
}

void main().catch((error) => {
  console.error("Tutoring payment schema backfill failed.");
  console.error(error);
  process.exitCode = 1;
});
