import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for governorates/{governorateId} — Locations
// Phase 3 (data foundation) + Phase 4 (Admin Locations module, the
// create/update/delete split below). Runs against a real Firestore
// emulator via `firebase emulators:exec` (see functions/package.json's
// test:rules script) — fake_cloud_firestore (used by the Dart unit tests)
// has no rules engine, so this is the only way to verify who can actually
// read/write this path.
//
// A note on "duplicate create": Firestore classifies a `.set()` as
// `create` only when no document exists yet at that path, and as `update`
// otherwise — this is automatic and based purely on document existence at
// commit time, not on which client method was called or what the caller
// intended. That means a rules-only guard can never distinguish "this was
// meant as a fresh add that collided with an existing id" from "this is a
// legitimate edit" once a document exists — both are the exact same
// `update` operation from the rules engine's point of view, and `update`
// must stay admin-only-unconditional for real edits (setGovernorateEnabled,
// the edit form, ...) to keep working. The `!exists(...)` clause on
// `create` below is still worth having (self-documenting, and always true
// whenever `create` fires at all, by Firestore's own definition of what
// "create" means) but it is NOT where duplicate-id protection actually
// lives. The real, race-safe guard is the Firestore transaction in
// FirestoreService.addGovernorate (read-then-conditionally-write, retried
// atomically by Firestore under a concurrent race) — see
// firestore_service_test.dart's "addGovernorate throws when the id already
// exists" test for that actual behavior.

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

describe("governorates/{governorateId} create (no existing doc)", () => {
  it("lets an admin create it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(governorateDoc(adminDb).set(sampleGovernorate));
  });

  it("denies a non-admin signed-in user from creating it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(governorateDoc(customerDb).set(sampleGovernorate));
  });

  it("denies an unauthenticated create", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(governorateDoc(anonDb).set(sampleGovernorate));
  });
});

describe("governorates/{governorateId} update (existing doc)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await governorateDoc(ctx.firestore()).set(sampleGovernorate);
    });
  });

  it("lets an admin update it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(governorateDoc(adminDb).set({ ...sampleGovernorate, order: 5 }));
  });

  it("denies a non-admin signed-in user from updating it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(governorateDoc(customerDb).set({ ...sampleGovernorate, order: 5 }));
  });

  it("denies an unauthenticated update", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(governorateDoc(anonDb).set({ ...sampleGovernorate, order: 5 }));
  });

  it("denies delete, even for an admin", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertFails(governorateDoc(adminDb).delete());
  });
});
