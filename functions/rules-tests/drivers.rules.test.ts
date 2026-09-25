import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for drivers/{driverId}'s create/update branches —
// specifically driver approval: a driver must start 'pending', can never
// change their own approvalStatus, and an admin may change approvalStatus
// alone. Also re-checks the existing ratingSum/ratingCount guard. See
// firestore.rules' own comment on the drivers/{driverId} block.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document on
// their own describe() blocks.
describe("drivers/{driverId} create/update rules", () => {
  let testEnv: RulesTestEnvironment;

  const DRIVER_ID = "driver-1";
  const OTHER_DRIVER_ID = "driver-2";
  const ADMIN_ID = "admin-1";

  // Same shape AuthService.signUp writes via Driver.toMap().
  function signupDriver(approvalStatus: unknown = "pending") {
    return {
      userId: DRIVER_ID,
      isAvailable: true,
      lastKnownLocation: null,
      ratingSum: 0,
      ratingCount: 0,
      approvalStatus,
    };
  }

  async function seedUsers() {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("users").doc(ADMIN_ID).set({ role: "admin" });
      await db.collection("users").doc(DRIVER_ID).set({ role: "driver" });
      await db.collection("users").doc(OTHER_DRIVER_ID).set({ role: "driver" });
    });
  }

  async function seedDriver(data: Record<string, unknown>) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("drivers").doc(DRIVER_ID).set(data);
    });
  }

  function driverDoc(db: FirebaseFirestore.Firestore, id = DRIVER_ID) {
    return db.collection("drivers").doc(id);
  }

  function asDriver() {
    return testEnv.authenticatedContext(DRIVER_ID).firestore();
  }

  function asAdmin() {
    return testEnv.authenticatedContext(ADMIN_ID).firestore();
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
    await seedUsers();
  });

  describe("create", () => {
    it("lets a driver create their own doc as pending", async () => {
      await assertSucceeds(driverDoc(asDriver()).set(signupDriver("pending")));
    });

    it("denies a driver creating their own doc as approved", async () => {
      await assertFails(driverDoc(asDriver()).set(signupDriver("approved")));
    });

    it("denies a driver creating their own doc as rejected", async () => {
      await assertFails(driverDoc(asDriver()).set(signupDriver("rejected")));
    });

    it("denies creating a doc with no approvalStatus at all", async () => {
      const data: Record<string, unknown> = signupDriver();
      delete data.approvalStatus;
      await assertFails(driverDoc(asDriver()).set(data));
    });

    it("denies creating another user's driver doc, even as pending", async () => {
      await assertFails(driverDoc(asDriver(), OTHER_DRIVER_ID).set(signupDriver("pending")));
    });

    it("denies creating a doc with a pre-inflated rating", async () => {
      await assertFails(
        driverDoc(asDriver()).set({ ...signupDriver("pending"), ratingSum: 50, ratingCount: 10 })
      );
    });

    it("denies an unauthenticated create", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(driverDoc(anonDb).set(signupDriver("pending")));
    });
  });

  describe("self update", () => {
    beforeEach(async () => {
      await seedDriver(signupDriver("pending"));
    });

    it("denies a driver approving themself", async () => {
      await assertFails(driverDoc(asDriver()).update({ approvalStatus: "approved" }));
    });

    it("denies a driver changing approvalStatus alongside an allowed field", async () => {
      await assertFails(
        driverDoc(asDriver()).update({ isAvailable: false, approvalStatus: "approved" })
      );
    });

    it("denies a legacy driver (no approvalStatus field) adding one", async () => {
      const legacy: Record<string, unknown> = signupDriver();
      delete legacy.approvalStatus;
      await seedDriver(legacy);
      await assertFails(driverDoc(asDriver()).update({ approvalStatus: "approved" }));
    });

    it("still lets a driver toggle their own availability", async () => {
      await assertSucceeds(driverDoc(asDriver()).update({ isAvailable: false }));
    });

    it("still lets a driver publish their own lastKnownLocation", async () => {
      await assertSucceeds(
        driverDoc(asDriver()).update({
          lastKnownLocation: { latitude: 33.5, longitude: 36.3, updatedAt: Date.now() },
        })
      );
    });

    it("still lets a legacy driver (no approvalStatus field) toggle availability", async () => {
      const legacy: Record<string, unknown> = signupDriver();
      delete legacy.approvalStatus;
      await seedDriver(legacy);
      await assertSucceeds(driverDoc(asDriver()).update({ isAvailable: false }));
    });

    it("still denies a driver changing their own ratingSum", async () => {
      await assertFails(driverDoc(asDriver()).update({ ratingSum: 50 }));
    });

    it("still denies a driver changing their own ratingCount", async () => {
      await assertFails(driverDoc(asDriver()).update({ ratingCount: 10 }));
    });

    it("denies another (non-admin) driver approving this driver", async () => {
      const otherDb = testEnv.authenticatedContext(OTHER_DRIVER_ID).firestore();
      await assertFails(driverDoc(otherDb).update({ approvalStatus: "approved" }));
    });

    it("denies an unauthenticated update", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(driverDoc(anonDb).update({ isAvailable: false }));
    });

    it("still denies delete, even for the driver themself", async () => {
      await assertFails(driverDoc(asDriver()).delete());
    });
  });

  describe("admin update", () => {
    beforeEach(async () => {
      await seedDriver(signupDriver("pending"));
    });

    it("lets an admin approve a driver", async () => {
      await assertSucceeds(driverDoc(asAdmin()).update({ approvalStatus: "approved" }));
    });

    it("lets an admin reject a driver", async () => {
      await assertSucceeds(driverDoc(asAdmin()).update({ approvalStatus: "rejected" }));
    });

    it("lets an admin approve a legacy driver with no approvalStatus field", async () => {
      const legacy: Record<string, unknown> = signupDriver();
      delete legacy.approvalStatus;
      await seedDriver(legacy);
      await assertSucceeds(driverDoc(asAdmin()).update({ approvalStatus: "approved" }));
    });

    it("denies an admin changing approvalStatus together with another field", async () => {
      await assertFails(
        driverDoc(asAdmin()).update({ approvalStatus: "approved", isAvailable: false })
      );
    });

    it("denies an admin changing a non-approval field on its own", async () => {
      await assertFails(driverDoc(asAdmin()).update({ isAvailable: false }));
    });

    it("denies an admin changing ratingSum/ratingCount", async () => {
      await assertFails(driverDoc(asAdmin()).update({ ratingSum: 50, ratingCount: 10 }));
    });

    it("denies an admin setting an unrecognized approvalStatus value", async () => {
      await assertFails(driverDoc(asAdmin()).update({ approvalStatus: "superApproved" }));
    });

    it("still denies an admin deleting a driver doc", async () => {
      await assertFails(driverDoc(asAdmin()).delete());
    });
  });
});
