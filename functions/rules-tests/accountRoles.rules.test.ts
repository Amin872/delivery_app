import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

import { deleteAccountData } from "../src/accounts";

// Phase 31 L1 (role-gated vendor/driver creation) and L2 (users/{uid}
// self-update whitelist). Payloads mirror the app's own writes:
// AuthService.signUp (Vendor/Driver/AppUser.toMap), FirestoreService.
// updateUserProfile/toggleFavoriteVendor, PushNotificationService and
// AuthService.signOut.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document.
describe("account roles (Phase 31 L1/L2)", () => {
  let testEnv: RulesTestEnvironment;

  const CUSTOMER = "customer-1";
  const OTHER_CUSTOMER = "customer-2";
  const DRIVER = "driver-1";
  const VENDOR = "vendor-1";
  const ADMIN = "admin-1";
  const NEW_USER = "new-user-1"; // signed up in Auth, no users doc yet

  // Compat FieldValue (the rules-unit-testing contexts use the compat API).
  let FieldValue: typeof import("firebase/compat/app").default.firestore.FieldValue;

  function db(uid: string) {
    return testEnv.authenticatedContext(uid).firestore();
  }

  function vendorDoc(ownerId: string, overrides: Record<string, unknown> = {}) {
    return {
      ownerId,
      name: "Store",
      description: "",
      imageUrl: null,
      logoUrl: null,
      isOpen: false,
      approvalStatus: "pending",
      ratingSum: 0,
      ratingCount: 0,
      category: "groceries",
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

  function driverDoc(uid: string, overrides: Record<string, unknown> = {}) {
    return {
      userId: uid,
      isAvailable: true,
      lastKnownLocation: null,
      ratingSum: 0,
      ratingCount: 0,
      approvalStatus: "pending",
      ...overrides,
    };
  }

  function userDoc(role: string, overrides: Record<string, unknown> = {}) {
    return {
      email: `${role}@example.com`,
      displayName: role,
      role,
      phoneNumber: null,
      favoriteVendorIds: [],
      ...overrides,
    };
  }

  before(async () => {
    FieldValue = (await import("firebase/compat/app")).default.firestore.FieldValue;
    await import("firebase/compat/firestore");
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
      await admin.doc(`users/${CUSTOMER}`).set(userDoc("customer", { phoneNumber: "+963 900 000 001" }));
      await admin.doc(`users/${OTHER_CUSTOMER}`).set(userDoc("customer"));
      await admin.doc(`users/${DRIVER}`).set(userDoc("driver"));
      await admin.doc(`users/${VENDOR}`).set(userDoc("vendor"));
      await admin.doc(`users/${ADMIN}`).set(userDoc("admin"));
    });
  });

  describe("L1: vendor creation is role-gated", () => {
    it("lets a vendor-role user create their storefront", async () => {
      await assertSucceeds(db(VENDOR).doc(`vendors/${VENDOR}`).set(vendorDoc(VENDOR)));
    });

    it("allows the signup window: no users doc yet (signUp writes vendors/{uid} first)", async () => {
      await assertSucceeds(db(NEW_USER).doc(`vendors/${NEW_USER}`).set(vendorDoc(NEW_USER)));
    });

    for (const [label, uid] of [
      ["a customer", CUSTOMER],
      ["a driver", DRIVER],
      ["an admin", ADMIN],
    ]) {
      it(`denies ${label} creating a vendor doc`, async () => {
        await assertFails(db(uid).doc(`vendors/${uid}`).set(vendorDoc(uid)));
      });
    }

    it("keeps the existing owner / approval / rating requirements", async () => {
      await assertFails(db(VENDOR).doc("vendors/other").set(vendorDoc(OTHER_CUSTOMER)));
      await assertFails(db(VENDOR).doc(`vendors/${VENDOR}`).set(vendorDoc(VENDOR, { approvalStatus: "approved" })));
      await assertFails(db(VENDOR).doc(`vendors/${VENDOR}`).set(vendorDoc(VENDOR, { ratingSum: 10 })));
      await assertFails(db(VENDOR).doc(`vendors/${VENDOR}`).set(vendorDoc(VENDOR, { ratingCount: 3 })));
      await assertFails(testEnv.unauthenticatedContext().firestore().doc("vendors/x").set(vendorDoc("x")));
    });
  });

  describe("L1: driver creation is role-gated", () => {
    it("lets a driver-role user create their own driver doc", async () => {
      await assertSucceeds(db(DRIVER).doc(`drivers/${DRIVER}`).set(driverDoc(DRIVER)));
    });

    it("allows the signup window: no users doc yet (signUp writes drivers/{uid} first)", async () => {
      await assertSucceeds(db(NEW_USER).doc(`drivers/${NEW_USER}`).set(driverDoc(NEW_USER)));
    });

    for (const [label, uid] of [
      ["a customer", CUSTOMER],
      ["a vendor", VENDOR],
      ["an admin", ADMIN],
    ]) {
      it(`denies ${label} creating a driver doc`, async () => {
        await assertFails(db(uid).doc(`drivers/${uid}`).set(driverDoc(uid)));
      });
    }

    it("keeps the existing self / approval / rating requirements", async () => {
      await assertFails(db(DRIVER).doc(`drivers/${OTHER_CUSTOMER}`).set(driverDoc(OTHER_CUSTOMER)));
      await assertFails(db(DRIVER).doc(`drivers/${DRIVER}`).set(driverDoc(DRIVER, { approvalStatus: "approved" })));
      await assertFails(db(DRIVER).doc(`drivers/${DRIVER}`).set(driverDoc(DRIVER, { ratingSum: 5 })));
      await assertFails(db(DRIVER).doc(`drivers/${DRIVER}`).set(driverDoc(DRIVER, { ratingCount: 1 })));
    });
  });

  describe("users/{uid} create (unchanged)", () => {
    it("still lets a new account create its profile as customer, driver or vendor", async () => {
      for (const role of ["customer", "driver", "vendor"]) {
        await testEnv.clearFirestore();
        await assertSucceeds(db(NEW_USER).doc(`users/${NEW_USER}`).set(userDoc(role)));
      }
    });

    it("still denies self-creating an admin profile", async () => {
      await assertFails(db(NEW_USER).doc(`users/${NEW_USER}`).set(userDoc("admin")));
    });
  });

  describe("L2: users/{uid} self-update whitelist", () => {
    const self = () => db(CUSTOMER).doc(`users/${CUSTOMER}`);

    it("allows the profile edit (displayName + phoneNumber, as updateUserProfile writes them)", async () => {
      await assertSucceeds(self().update({ displayName: "New Name", phoneNumber: "+963 900 000 009" }));
      await assertSucceeds(self().update({ displayName: "New Name", phoneNumber: null }));
    });

    it("allows favorites via arrayUnion / arrayRemove", async () => {
      await assertSucceeds(self().update({ favoriteVendorIds: FieldValue.arrayUnion("vendor-9") }));
      await assertSucceeds(self().update({ favoriteVendorIds: FieldValue.arrayRemove("vendor-9") }));
    });

    it("allows the push fields: fcmToken set, fcmToken delete (sign-out), locale", async () => {
      await assertSucceeds(self().update({ fcmToken: "token-1" }));
      await assertSucceeds(self().update({ fcmToken: FieldValue.delete() }));
      await assertSucceeds(self().update({ locale: "en" }));
      await assertSucceeds(self().update({ fcmToken: "token-2", locale: "ar" }));
    });

    it("denies changing role, alone or with allowed fields", async () => {
      await assertFails(self().update({ role: "admin" }));
      await assertFails(self().update({ role: "vendor" }));
      await assertFails(self().update({ displayName: "X", role: "driver" }));
    });

    it("denies changing email (not an app-updated field)", async () => {
      await assertFails(self().update({ email: "other@example.com" }));
    });

    it("denies unknown fields and injections next to legitimate ones", async () => {
      for (const extra of [
        { isAdmin: true },
        { approvalStatus: "approved" },
        { ratingSum: 100 },
        { disabled: false },
      ]) {
        await assertFails(self().update(extra));
        await assertFails(self().update({ locale: "en", ...extra }));
      }
    });

    it("denies a full set() that adds a field outside the whitelist", async () => {
      await assertFails(self().set({ ...userDoc("customer"), nickname: "x" }));
    });

    it("denies updating another user's doc, including as an admin", async () => {
      await assertFails(db(OTHER_CUSTOMER).doc(`users/${CUSTOMER}`).update({ displayName: "Hijack" }));
      await assertFails(db(ADMIN).doc(`users/${CUSTOMER}`).update({ displayName: "Admin edit" }));
      await assertFails(db(ADMIN).doc(`users/${CUSTOMER}`).update({ role: "vendor" }));
    });

    it("keeps admin read access to users unchanged", async () => {
      await assertSucceeds(db(ADMIN).doc(`users/${CUSTOMER}`).get());
    });
  });

  // Phase 31 M1: the profile can't be deleted (and so can't be recreated
  // with another role) from any client; account deletion removes the Auth
  // account and onAuthUserDeleted cleans up server-side.
  describe("M1: users/{uid} delete", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`users/${CUSTOMER}/addresses/home`).set({ userId: CUSTOMER, addressText: "Mezzeh" });
        await ctx.firestore().doc(`users/${CUSTOMER}/addresses/work`).set({ userId: CUSTOMER, addressText: "Malki" });
      });
    });

    it("denies every role deleting its own profile", async () => {
      for (const uid of [CUSTOMER, DRIVER, VENDOR, ADMIN]) {
        await assertFails(db(uid).doc(`users/${uid}`).delete());
      }
    });

    it("denies deleting someone else's profile, including as an admin", async () => {
      await assertFails(db(OTHER_CUSTOMER).doc(`users/${CUSTOMER}`).delete());
      await assertFails(db(ADMIN).doc(`users/${CUSTOMER}`).delete());
    });

    it("rejects the old client-side account deletion batch as a whole (addresses stay)", async () => {
      const client = db(CUSTOMER);
      const batch = client.batch();
      batch.delete(client.doc(`users/${CUSTOMER}/addresses/home`));
      batch.delete(client.doc(`users/${CUSTOMER}/addresses/work`));
      batch.delete(client.doc(`users/${CUSTOMER}`));
      await assertFails(batch.commit());

      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const remaining = await ctx.firestore().collection(`users/${CUSTOMER}/addresses`).get();
        if (remaining.size !== 2) throw new Error(`expected 2 addresses, found ${remaining.size}`);
      });
    });

    it("keeps ordinary address management (deleting one saved address) working", async () => {
      await assertSucceeds(db(CUSTOMER).doc(`users/${CUSTOMER}/addresses/work`).delete());
    });

    it("keeps the role immutable: no delete-and-recreate, no overwrite with another role", async () => {
      await assertFails(db(VENDOR).doc(`users/${VENDOR}`).delete());
      await assertFails(db(VENDOR).doc(`users/${VENDOR}`).set(userDoc("customer")));
      await assertFails(db(CUSTOMER).doc(`users/${CUSTOMER}`).set(userDoc("vendor")));
      await assertFails(db(CUSTOMER).doc(`users/${CUSTOMER}`).update({ role: "driver" }));
    });
  });

  // The onAuthUserDeleted cleanup (deleteAccountData) against the real
  // Firestore emulator, via a rules-bypassing context — the Admin SDK in
  // production also bypasses rules.
  describe("M1: account cleanup against the emulator", () => {
    const HISTORY = ["orders/o1", "reviews/o1", `vendors/${VENDOR}`, `drivers/${DRIVER}`];

    async function seedHistory() {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const admin = ctx.firestore();
        await admin.doc("orders/o1").set({ customerId: CUSTOMER, vendorId: VENDOR, driverId: DRIVER, status: "delivered" });
        await admin.doc("reviews/o1").set({ orderId: "o1", customerId: CUSTOMER, vendorRating: 5, driverRating: 5 });
        await admin.doc(`vendors/${VENDOR}`).set({ ownerId: VENDOR, approvalStatus: "approved" });
        await admin.doc(`drivers/${DRIVER}`).set({ userId: DRIVER, approvalStatus: "approved" });
      });
    }

    async function exists(path: string): Promise<boolean> {
      let found = false;
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        found = (await ctx.firestore().doc(path).get()).exists;
      });
      return found;
    }

    it("deletes users/{uid} and all addresses, keeping orders, reviews and vendor/driver records", async () => {
      await seedHistory();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        for (const id of ["home", "work", "parents"]) {
          await ctx.firestore().doc(`users/${CUSTOMER}/addresses/${id}`).set({ userId: CUSTOMER, addressText: id });
        }
        await ctx.firestore().doc(`users/${OTHER_CUSTOMER}/addresses/home`).set({ userId: OTHER_CUSTOMER, addressText: "x" });
        const result = await deleteAccountData(ctx.firestore() as never, CUSTOMER);
        if (result.addressesDeleted !== 3) throw new Error(`expected 3 addresses deleted, got ${result.addressesDeleted}`);
      });

      for (const path of [`users/${CUSTOMER}`, `users/${CUSTOMER}/addresses/home`, `users/${CUSTOMER}/addresses/parents`]) {
        if (await exists(path)) throw new Error(`${path} should be deleted`);
      }
      for (const path of [...HISTORY, `users/${OTHER_CUSTOMER}`, `users/${OTHER_CUSTOMER}/addresses/home`]) {
        if (!(await exists(path))) throw new Error(`${path} should be kept`);
      }
    });

    it("is safe when the profile is already gone and there are no addresses", async () => {
      await seedHistory();
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const result = await deleteAccountData(ctx.firestore() as never, "never-had-a-profile");
        if (result.addressesDeleted !== 0) throw new Error("expected nothing deleted");
      });
      for (const path of HISTORY) {
        if (!(await exists(path))) throw new Error(`${path} should be kept`);
      }
    });
  });
});
