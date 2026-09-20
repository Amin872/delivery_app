import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for cities/{cityId} — Locations Phase 1/2 (data
// foundation) + Phase 4 (Admin Locations module, the create/update/delete
// split below). Cities never had a dedicated rules test file before this
// phase (Phase 1-3 only covered governorates); see governorates.rules.test.ts
// for the full explanation of why "duplicate create" is enforced by
// FirestoreService.addCity's transaction, not by the rules `!exists(...)`
// clause alone (Firestore classifies create/update purely by document
// existence at commit time, not by caller intent).

let testEnv: RulesTestEnvironment;

const CITY_ID = "damascus";
const sampleCity = { nameEn: "Damascus", nameAr: "دمشق", enabled: true, order: 0 };

function cityDoc(db: FirebaseFirestore.Firestore) {
  return db.collection("cities").doc(CITY_ID);
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "delivery-app-rules-test",
    firestore: {
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

describe("cities/{cityId} reads", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await cityDoc(ctx.firestore()).set(sampleCity);
    });
  });

  it("lets an unauthenticated user read it (public read)", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertSucceeds(cityDoc(anonDb).get());
  });

  it("lets any signed-in user read it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertSucceeds(cityDoc(customerDb).get());
  });
});

describe("cities/{cityId} create (no existing doc)", () => {
  it("lets an admin create it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(cityDoc(adminDb).set(sampleCity));
  });

  it("denies a non-admin signed-in user from creating it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(cityDoc(customerDb).set(sampleCity));
  });

  it("denies an unauthenticated create", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(cityDoc(anonDb).set(sampleCity));
  });
});

describe("cities/{cityId} update (existing doc)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await cityDoc(ctx.firestore()).set(sampleCity);
    });
  });

  it("lets an admin update it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(cityDoc(adminDb).set({ ...sampleCity, governorateId: "damascus" }));
  });

  it("denies a non-admin signed-in user from updating it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(cityDoc(customerDb).set({ ...sampleCity, order: 5 }));
  });

  it("denies an unauthenticated update", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(cityDoc(anonDb).set({ ...sampleCity, order: 5 }));
  });

  it("denies delete, even for an admin", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertFails(cityDoc(adminDb).delete());
  });
});
