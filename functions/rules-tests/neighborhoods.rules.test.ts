import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for neighborhoods/{neighborhoodId} — Phase 4
// Location & Address Architecture (Governorate -> City -> Neighborhood).
// Deliberately mirrors districts.rules.test.ts's own coverage exactly (same
// cityId-must-exist referential check on both create and update) — see
// models/neighborhood.dart's doc comment for why this is a standalone
// collection rather than a reuse of districts/{districtId}.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts documents on its own describe().
describe("neighborhoods/{neighborhoodId} rules", () => {
  let testEnv: RulesTestEnvironment;

  const NEIGHBORHOOD_ID = "damascus_mazzeh";
  const EXISTING_CITY_ID = "damascus";
  const MISSING_CITY_ID = "nonexistent-city";

  function sampleNeighborhood(cityId: string) {
    return { nameEn: "Al-Mazzeh", nameAr: "المزة", cityId, enabled: true, order: 0 };
  }

  function neighborhoodDoc(db: FirebaseFirestore.Firestore) {
    return db.collection("neighborhoods").doc(NEIGHBORHOOD_ID);
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
        await neighborhoodDoc(ctx.firestore()).set(sampleNeighborhood(EXISTING_CITY_ID));
      });
    });

    it("lets an unauthenticated user read it (public read)", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertSucceeds(neighborhoodDoc(anonDb).get());
    });

    it("lets any signed-in user read it", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertSucceeds(neighborhoodDoc(customerDb).get());
    });
  });

  describe("create (no existing doc)", () => {
    it("denies a non-admin signed-in user, even with an existing city", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertFails(neighborhoodDoc(customerDb).set(sampleNeighborhood(EXISTING_CITY_ID)));
    });

    it("denies an unauthenticated create", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(neighborhoodDoc(anonDb).set(sampleNeighborhood(EXISTING_CITY_ID)));
    });

    it("lets an admin create it when the referenced city exists", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertSucceeds(neighborhoodDoc(adminDb).set(sampleNeighborhood(EXISTING_CITY_ID)));
    });

    it("denies an admin create when the referenced city does not exist", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(neighborhoodDoc(adminDb).set(sampleNeighborhood(MISSING_CITY_ID)));
    });
  });

  describe("update (existing doc)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await neighborhoodDoc(ctx.firestore()).set(sampleNeighborhood(EXISTING_CITY_ID));
      });
    });

    it("lets an admin update it when the (possibly new) referenced city exists", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertSucceeds(
        neighborhoodDoc(adminDb).set({ ...sampleNeighborhood(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies an admin update when the referenced city does not exist", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(neighborhoodDoc(adminDb).set(sampleNeighborhood(MISSING_CITY_ID)));
    });

    it("denies a non-admin signed-in user from updating it", async () => {
      const customerDb = testEnv.authenticatedContext("customer-1").firestore();
      await assertFails(
        neighborhoodDoc(customerDb).set({ ...sampleNeighborhood(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies an unauthenticated update", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(
        neighborhoodDoc(anonDb).set({ ...sampleNeighborhood(EXISTING_CITY_ID), order: 5 })
      );
    });

    it("denies delete, even for an admin", async () => {
      const adminDb = testEnv.authenticatedContext("admin-1").firestore();
      await assertFails(neighborhoodDoc(adminDb).delete());
    });
  });
});
