import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for districts/{districtId} — Locations Phase 1
// District data foundation (Governorate -> City -> District architecture).
// Unlike cities/{cityId} and governorates/{governorateId}, both create AND
// update here additionally require the referenced city (`cityId`) to
// actually exist — a new, stricter pattern introduced specifically for
// districts (neither sibling collection's rules cross-check their own
// parent-reference field). See governorates.rules.test.ts's comment for
// why real duplicate-id protection is enforced by
// FirestoreService.addDistrict's transaction, not by the rules
// `!exists(...)` clause alone.
//
// Everything below is wrapped in one top-level describe() rather than using
// file-scoped before()/beforeEach() directly — mocha treats hooks declared
// outside any describe() as ROOT-SUITE hooks shared across every *.test.ts
// file mocha loads in this run, executed in file-load order before any
// test in the whole run, regardless of which file that test belongs to.
// This file is the first one that needs a doc seeded in its own setup
// (cities/damascus) to survive into its own test bodies; a later-loaded
// sibling file's own root-level beforeEach (e.g. governorates.rules.test.ts,
// which also calls clearFirestore()) would otherwise wipe it out before
// this file's own tests run. Scoping these hooks inside a describe() block
// makes them suite-level instead, so they run in the correct order
// relative to this file's own tests no matter what other files declare.
describe("districts/{districtId} rules", () => {
  let testEnv: RulesTestEnvironment;

  const DISTRICT_ID = "al_mazzeh";
  const EXISTING_CITY_ID = "damascus";
  const MISSING_CITY_ID = "nonexistent-city";

  function sampleDistrict(cityId: string) {
    return { nameEn: "Al-Mazzeh", nameAr: "المزة", cityId, enabled: true, order: 0 };
  }

  function districtDoc(db: FirebaseFirestore.Firestore) {
    return db.collection("districts").doc(DISTRICT_ID);
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
      await ctx
        .firestore()
        .collection("cities")
        .doc(EXISTING_CITY_ID)
        .set({ nameEn: "Damascus", nameAr: "دمشق", enabled: true, order: 0 });
    });
  });

  describe("reads", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await districtDoc(ctx.firestore()).set(sampleDistrict(EXISTING_CITY_ID));
      });
    });

    it("lets an unauthenticated user read it (public read)", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(districtDoc(anonDb).get());
    });

    it("lets any signed-in user read it", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertSucceeds(districtDoc(customerDb).get());
    });
  });

  describe("create (no existing doc)", () => {
    it("denies a non-admin signed-in user, even with an existing city", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertFails(districtDoc(customerDb).set(sampleDistrict(EXISTING_CITY_ID)));
    });

    it("denies an unauthenticated create", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(districtDoc(anonDb).set(sampleDistrict(EXISTING_CITY_ID)));
    });

    it("lets an admin create it when the referenced city exists", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertSucceeds(districtDoc(adminDb).set(sampleDistrict(EXISTING_CITY_ID)));
    });

    it("denies an admin create when the referenced city does not exist", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(districtDoc(adminDb).set(sampleDistrict(MISSING_CITY_ID)));
    });
  });

  describe("update (existing doc)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await districtDoc(ctx.firestore()).set(sampleDistrict(EXISTING_CITY_ID));
      });
    });

    it("lets an admin update it when the (possibly new) referenced city exists", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertSucceeds(
        districtDoc(adminDb).set({ ...sampleDistrict(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies an admin update when the referenced city does not exist", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(districtDoc(adminDb).set(sampleDistrict(MISSING_CITY_ID)));
    });

    it("denies a non-admin signed-in user from updating it", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertFails(
        districtDoc(customerDb).set({ ...sampleDistrict(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies an unauthenticated update", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(
        districtDoc(anonDb).set({ ...sampleDistrict(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies delete, even for an admin", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(districtDoc(adminDb).delete());
    });
  });
});
