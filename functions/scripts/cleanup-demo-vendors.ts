/**
 * Companion to seed-demo-vendors.ts: deletes exactly the documents that
 * script created — matched by their deterministic seed-vendor-01..10 IDs,
 * not a broad query — from the LIVE delivery-app-syria-2026 project.
 *
 *   GOOGLE_APPLICATION_CREDENTIALS="$env:APPDATA\firebase\<you>_application_default_credentials.json" \
 *   npx ts-node scripts/cleanup-demo-vendors.ts --yes
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "delivery-app-syria-2026";
const VENDOR_COUNT = 10;

async function main() {
  if (!process.argv.includes("--yes")) {
    throw new Error(
      `Refusing to run without --yes — this deletes documents from the LIVE ${PROJECT_ID} project.`
    );
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  for (let i = 0; i < VENDOR_COUNT; i++) {
    const vendorId = `seed-vendor-${String(i + 1).padStart(2, "0")}`;
    const vendorRef = db.collection("vendors").doc(vendorId);
    const menuItems = await vendorRef.collection("menuItems").listDocuments();
    await Promise.all(menuItems.map((doc) => doc.delete()));
    await vendorRef.delete();
    console.log(`Deleted ${vendorId} and its ${menuItems.length} menu items.`);
  }

  console.log("Done.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
