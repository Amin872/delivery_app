import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Phase 31 rules hardening for vendors/{vendorId} and its menuItems:
// H2 (no fabricated ratings at creation), L4 (admin approvalStatus values)
// and M2 (a menu item's vendorId must match the vendor it lives under).
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document.
describe("vendors/{vendorId} and menuItems (Phase 31)", () => {
  let testEnv: RulesTestEnvironment;

  const OWNER = "vendor-owner-1";
  const OTHER_OWNER = "vendor-owner-2";
  const ADMIN = "admin-1";

  // The shape AuthService.signUp writes for a new vendor (Vendor.toMap()).
  function newVendor(ownerId: string, overrides: Record<string, unknown> = {}) {
    return {
      ownerId,
      name: "Falafel House",
      description: "",
      imageUrl: null,
      logoUrl: null,
      isOpen: false,
      approvalStatus: "pending",
      ratingSum: 0,
      ratingCount: 0,
      category: "restaurants",
      city: "damascus",
      deliveryFee: null,
      etaMinMinutes: null,
      etaMaxMinutes: null,
      minimumOrderAmount: null,
      openTime: null,
      closeTime: null,
      pickupAddress: null,
      pickupLatitude: null,
      pickupLongitude: null,
      ...overrides,
    };
  }

  // The shape MenuManagementScreen writes (MenuItem.toMap()).
  function menuItem(vendorId: string, overrides: Record<string, unknown> = {}) {
    return {
      vendorId,
      name: "Falafel wrap",
      price: 2000,
      imageUrl: null,
      available: true,
      description: null,
      section: null,
      orderCount: 0,
      ...overrides,
    };
  }

  function db(uid: string) {
    return testEnv.authenticatedContext(uid).firestore();
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
      const admin = ctx.firestore();
      await admin.doc(`users/${ADMIN}`).set({ role: "admin", email: "a@example.com", displayName: "Admin" });
      await admin.doc(`users/${OWNER}`).set({ role: "vendor", email: "o@example.com", displayName: "Owner" });
      await admin.doc(`users/${OTHER_OWNER}`).set({ role: "vendor", email: "p@example.com", displayName: "Other" });
    });
  });

  describe("vendor create (H2)", () => {
    it("allows the signup payload with zero ratings", async () => {
      await assertSucceeds(db(OWNER).doc(`vendors/${OWNER}`).set(newVendor(OWNER)));
    });

    it("allows a payload with the rating fields absent", async () => {
      const payload: Record<string, unknown> = newVendor(OWNER);
      delete payload.ratingSum;
      delete payload.ratingCount;
      await assertSucceeds(db(OWNER).doc(`vendors/${OWNER}`).set(payload));
    });

    it("denies a fabricated ratingSum", async () => {
      await assertFails(db(OWNER).doc(`vendors/${OWNER}`).set(newVendor(OWNER, { ratingSum: 500 })));
    });

    it("denies a fabricated ratingCount", async () => {
      await assertFails(db(OWNER).doc(`vendors/${OWNER}`).set(newVendor(OWNER, { ratingCount: 100 })));
    });

    it("still denies a non-pending approvalStatus or someone else's ownerId", async () => {
      await assertFails(db(OWNER).doc(`vendors/${OWNER}`).set(newVendor(OWNER, { approvalStatus: "approved" })));
      await assertFails(db(OWNER).doc(`vendors/${OWNER}`).set(newVendor(OTHER_OWNER)));
    });
  });

  describe("admin approvalStatus values (L4)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("vendors/v1").set(newVendor(OWNER));
        // A legacy doc written before approvalStatus existed.
        const legacy: Record<string, unknown> = newVendor(OTHER_OWNER);
        delete legacy.approvalStatus;
        await ctx.firestore().doc("vendors/legacy").set(legacy);
      });
    });

    for (const status of ["pending", "approved", "rejected"]) {
      it(`lets an admin set approvalStatus to '${status}'`, async () => {
        await assertSucceeds(db(ADMIN).doc("vendors/v1").update({ approvalStatus: status }));
      });
    }

    it("denies an admin setting an unknown approvalStatus", async () => {
      for (const status of ["superApproved", "APPROVED", "", 1, null]) {
        await assertFails(db(ADMIN).doc("vendors/v1").update({ approvalStatus: status }));
      }
    });

    it("still lets an admin edit whitelisted fields (with or without an approval change)", async () => {
      await assertSucceeds(db(ADMIN).doc("vendors/v1").update({ isOpen: true, deliveryFee: 1500 }));
      await assertSucceeds(db(ADMIN).doc("vendors/v1").update({ approvalStatus: "approved", isOpen: true }));
      // Editing a legacy doc's other fields doesn't trip the approval check.
      await assertSucceeds(db(ADMIN).doc("vendors/legacy").update({ minimumOrderAmount: 5000 }));
    });

    it("still denies an admin writing outside the whitelist (e.g. ratings or name)", async () => {
      await assertFails(db(ADMIN).doc("vendors/v1").update({ ratingSum: 50 }));
      await assertFails(db(ADMIN).doc("vendors/v1").update({ name: "Renamed" }));
    });
  });

  describe("menuItems vendorId binding (M2)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc("vendors/v1").set(newVendor(OWNER, { approvalStatus: "approved" }));
        await ctx.firestore().doc("vendors/v2").set(newVendor(OTHER_OWNER, { approvalStatus: "approved" }));
        await ctx.firestore().doc("vendors/v1/menuItems/existing").set(menuItem("v1", { orderCount: 3 }));
      });
    });

    it("lets the owner create an item whose vendorId matches its vendor", async () => {
      await assertSucceeds(db(OWNER).collection("vendors/v1/menuItems").add(menuItem("v1")));
    });

    it("denies creating an item that names another vendor (or none)", async () => {
      await assertFails(db(OWNER).collection("vendors/v1/menuItems").add(menuItem("v2")));
      const noVendor: Record<string, unknown> = menuItem("v1");
      delete noVendor.vendorId;
      await assertFails(db(OWNER).collection("vendors/v1/menuItems").add(noVendor));
    });

    it("lets the owner update an item keeping the matching vendorId (full set, as the app does)", async () => {
      await assertSucceeds(
        db(OWNER).doc("vendors/v1/menuItems/existing").set(menuItem("v1", { price: 2500, orderCount: 3 }))
      );
      await assertSucceeds(db(OWNER).doc("vendors/v1/menuItems/existing").update({ available: false }));
    });

    it("denies re-pointing an existing item's vendorId", async () => {
      await assertFails(db(OWNER).doc("vendors/v1/menuItems/existing").update({ vendorId: "v2" }));
    });

    it("still denies another vendor's owner", async () => {
      await assertFails(db(OTHER_OWNER).collection("vendors/v1/menuItems").add(menuItem("v1")));
    });
  });
});
