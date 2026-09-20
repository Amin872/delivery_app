import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for Locations Phase 3's governorates/{governorateId}
// collection — same public-read/admin-write shape as cities/promotions.
// Runs against a real Firestore emulator via `firebase emulators:exec` (see
// functions/package.json's test:rules script) — fake_cloud_firestore (used
// by the Dart unit tests) has no rules engine, so this is the only way to
// verify who can actually read/write this path.

let testEnv: RulesTestEnvironment;

const GOVERNORATE_ID = "damascus";
const sampleGovernorate = { nameEn: "Damascus", nameAr: "دمشق", enabled: true, order: 0 };

function governorateDoc(db: FirebaseFirestore.Firestore) {
  return db.collection("governorates").doc(GOVERNORATE_ID);
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "delivery-app-rules-test",
    firestore: {
      // See driverLocation.rules.test.ts for why this is process.cwd()-
      // relative rather than __dirname/import.meta.url.
      rules: fs.readFileSync(path.resolve(process.cwd(), "../firestore.rules"), "utf8"),
      host: "127.0.0.1",
      port: 8080,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore().collection("users").doc("admin-1").set({ role: "admin" });
  });
});

describe("governorates/{governorateId} reads", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await governorateDoc(ctx.firestore()).set(sampleGovernorate);
    });
  });

  it("lets an unauthenticated user read it (public read)", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(governorateDoc(anonDb).get());
  });

  it("lets any signed-in user read it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertSucceeds(governorateDoc(customerDb).get());
  });
});

describe("governorates/{governorateId} writes", () => {
  it("lets an admin write it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(governorateDoc(adminDb).set(sampleGovernorate));
  });

  it("denies a non-admin signed-in user from writing it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(governorateDoc(customerDb).set(sampleGovernorate));
  });

  it("denies an unauthenticated write", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(governorateDoc(anonDb).set(sampleGovernorate));
  });
});
