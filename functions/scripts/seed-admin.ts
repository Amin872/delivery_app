/**
 * One-off script: creates a single admin test account directly against the
 * Firebase Auth + Firestore *emulators* (never the live project) for
 * mobile/integration_test/'s E2E suite. Admin accounts have no self-service
 * signup path — see firestore.rules' users/{userId} create rule and
 * mobile/lib/features/auth/screens/signup_screen.dart's _selfServiceRoles —
 * so an Admin-SDK write, which bypasses those rules by design, is the only
 * way to get one into existence at all.
 *
 * Not part of the deployed Cloud Functions build: lives outside tsconfig's
 * "src" rootDir, so `npm run build` never touches it. Run directly:
 *
 *   FIRESTORE_EMULATOR_HOST=localhost:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 \
 *   npx ts-node scripts/seed-admin.ts
 */
import * as admin from "firebase-admin";

const EMAIL = "admin@e2e.test";
const PASSWORD = "TestAdmin123!";
const DISPLAY_NAME = "E2E Admin";

async function main() {
  if (!process.env.FIRESTORE_EMULATOR_HOST || !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error(
      "Refusing to run without FIRESTORE_EMULATOR_HOST and FIREBASE_AUTH_EMULATOR_HOST set — " +
        "this script uses the Admin SDK to bypass firestore.rules, which must never touch the live project."
    );
  }

  admin.initializeApp({ projectId: "delivery-app-syria-2026" });

  const auth = admin.auth();
  const db = admin.firestore();

  let uid: string;
  try {
    const existing = await auth.getUserByEmail(EMAIL);
    uid = existing.uid;
    console.log(`Admin auth user already exists: ${uid}`);
  } catch {
    const created = await auth.createUser({
      email: EMAIL,
      password: PASSWORD,
      displayName: DISPLAY_NAME,
    });
    uid = created.uid;
    console.log(`Created admin auth user: ${uid}`);
  }

  await db.collection("users").doc(uid).set({
    email: EMAIL,
    displayName: DISPLAY_NAME,
    role: "admin",
    phoneNumber: null,
  });
  console.log(`Seeded users/${uid} with role: admin`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
