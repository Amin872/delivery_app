import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Locks in that phone numbers stay private: users/{uid} (which holds
// phoneNumber) is readable only by its owner and admins, and saved
// addresses (which may hold a contact phone) only by their owner — even
// between participants of the same order. Order participants reach each
// other's phone only through the getOrderContact callable
// (functions/src/contacts.ts), never by reading these documents.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document.
describe("users/{uid} and addresses privacy", () => {
  let testEnv: RulesTestEnvironment;

  const CUSTOMER = "customer-1";
  const OTHER_CUSTOMER = "customer-2";
  const DRIVER = "driver-1";
  const VENDOR_OWNER = "vendor-owner-1";
  const ADMIN = "admin-1";

  function read(uid: string, docPath: string) {
    return testEnv.authenticatedContext(uid).firestore().doc(docPath).get();
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
      const db = ctx.firestore();
      const user = (role: string, phone: string) => ({
        email: `${role}@example.com`,
        displayName: role,
        role,
        phoneNumber: phone,
      });
      await db.doc(`users/${CUSTOMER}`).set(user("customer", "+963 900 000 001"));
      await db.doc(`users/${OTHER_CUSTOMER}`).set(user("customer", "+963 900 000 002"));
      await db.doc(`users/${DRIVER}`).set(user("driver", "+963 900 000 003"));
      await db.doc(`users/${VENDOR_OWNER}`).set(user("vendor", "+963 900 000 004"));
      await db.doc(`users/${ADMIN}`).set(user("admin", "+963 900 000 005"));
      await db.doc(`users/${CUSTOMER}/addresses/home`).set({
        userId: CUSTOMER,
        addressText: "Mezzeh",
        phone: "+963 900 000 009",
        isDefault: true,
      });
      // The three of them share an active order — which must still not
      // open up each other's user documents.
      await db.doc("vendors/vendor-1").set({ ownerId: VENDOR_OWNER });
      await db.doc("orders/o1").set({
        customerId: CUSTOMER,
        vendorId: "vendor-1",
        driverId: DRIVER,
        status: "delivering",
        items: [],
        total: 10,
        deliveryAddress: "Mezzeh",
        createdAt: Date.now(),
      });
    });
  });

  describe("users/{uid}", () => {
    it("lets a user read their own document", async () => {
      await assertSucceeds(read(CUSTOMER, `users/${CUSTOMER}`));
    });

    it("lets an admin read any user document", async () => {
      await assertSucceeds(read(ADMIN, `users/${CUSTOMER}`));
      await assertSucceeds(read(ADMIN, `users/${DRIVER}`));
    });

    it("denies another customer", async () => {
      await assertFails(read(OTHER_CUSTOMER, `users/${CUSTOMER}`));
    });

    it("denies the order's driver reading the customer's document", async () => {
      await assertFails(read(DRIVER, `users/${CUSTOMER}`));
    });

    it("denies the customer reading their driver's document", async () => {
      await assertFails(read(CUSTOMER, `users/${DRIVER}`));
    });

    it("denies the order's vendor reading the customer's document", async () => {
      await assertFails(read(VENDOR_OWNER, `users/${CUSTOMER}`));
    });

    it("denies the customer reading the vendor owner's document", async () => {
      await assertFails(read(CUSTOMER, `users/${VENDOR_OWNER}`));
    });

    it("denies an unauthenticated read", async () => {
      await assertFails(testEnv.unauthenticatedContext().firestore().doc(`users/${CUSTOMER}`).get());
    });
  });

  describe("users/{uid}/addresses", () => {
    it("lets the owner read their own address", async () => {
      await assertSucceeds(read(CUSTOMER, `users/${CUSTOMER}/addresses/home`));
    });

    for (const [label, uid] of [
      ["the order's driver", DRIVER],
      ["the order's vendor", VENDOR_OWNER],
      ["another customer", OTHER_CUSTOMER],
    ]) {
      it(`denies ${label}`, async () => {
        await assertFails(read(uid, `users/${CUSTOMER}/addresses/home`));
      });
    }
  });

  // Phase 28: the push fields a user's own app maintains on their user doc.
  // Only the owner may write them (existing self-update branch), and doing
  // so can never touch role.
  describe("users/{uid} notification fields (fcmToken, locale)", () => {
    function userDoc(uid: string, target: string) {
      return testEnv.authenticatedContext(uid).firestore().doc(`users/${target}`);
    }

    it("lets a user set their own fcmToken and locale", async () => {
      await assertSucceeds(userDoc(CUSTOMER, CUSTOMER).update({ fcmToken: "tok-1", locale: "en" }));
    });

    it("lets a user clear their own fcmToken (sign-out)", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().doc(`users/${CUSTOMER}`).update({ fcmToken: "tok-old" });
      });
      // The rules-unit-testing contexts use the compat Firestore API.
      const firebase = (await import("firebase/compat/app")).default;
      await import("firebase/compat/firestore");
      await assertSucceeds(
        userDoc(CUSTOMER, CUSTOMER).update({ fcmToken: firebase.firestore.FieldValue.delete() })
      );
    });

    for (const [label, uid] of [
      ["another customer", OTHER_CUSTOMER],
      ["the order's driver", DRIVER],
      ["the order's vendor", VENDOR_OWNER],
      ["an admin", ADMIN],
    ]) {
      it(`denies ${label} changing someone else's fcmToken/locale`, async () => {
        await assertFails(userDoc(uid, CUSTOMER).update({ fcmToken: "hijacked" }));
        await assertFails(userDoc(uid, CUSTOMER).update({ locale: "en" }));
      });
    }

    it("still denies a user changing their own role alongside the push fields", async () => {
      await assertFails(userDoc(CUSTOMER, CUSTOMER).update({ locale: "en", role: "admin" }));
    });

    it("still denies an unauthenticated write", async () => {
      await assertFails(
        testEnv.unauthenticatedContext().firestore().doc(`users/${CUSTOMER}`).update({ fcmToken: "x" })
      );
    });
  });
});
