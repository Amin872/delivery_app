import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// reviews/{orderId}: the existing create-once + delivered-order cross-checks,
// plus Phase 31 (L3) — exactly Review.toMap()'s keys and a bounded comment.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document.
describe("reviews/{orderId}", () => {
  let testEnv: RulesTestEnvironment;

  const CUSTOMER = "customer-1";
  const OTHER_CUSTOMER = "customer-2";
  const ORDER = "order-1";

  // The payload RateOrderDialog writes via FirestoreService.submitReview.
  function review(overrides: Record<string, unknown> = {}) {
    return {
      orderId: ORDER,
      customerId: CUSTOMER,
      vendorId: "vendor-1",
      driverId: "driver-1",
      vendorRating: 5,
      driverRating: 4,
      comment: "Great food, fast delivery.",
      createdAt: Date.now(),
      ...overrides,
    };
  }

  function reviewDoc(uid: string) {
    return testEnv.authenticatedContext(uid).firestore().doc(`reviews/${ORDER}`);
  }

  async function seedOrder(status = "delivered") {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().doc(`orders/${ORDER}`).set({
        customerId: CUSTOMER,
        vendorId: "vendor-1",
        driverId: "driver-1",
        status,
        items: [],
        total: 10,
        deliveryAddress: "Mezzeh",
        createdAt: Date.now(),
      });
    });
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
    await seedOrder();
  });

  describe("valid payloads", () => {
    it("accepts the app's payload with a comment", async () => {
      await assertSucceeds(reviewDoc(CUSTOMER).set(review()));
    });

    it("accepts a null comment (the dialog sends null when left empty)", async () => {
      await assertSucceeds(reviewDoc(CUSTOMER).set(review({ comment: null })));
    });

    it("accepts a comment of exactly 1000 characters", async () => {
      await assertSucceeds(reviewDoc(CUSTOMER).set(review({ comment: "x".repeat(1000) })));
    });

  });

  // Phase 31 (M3 option 2): reads require sign-in; the schema is unchanged.
  describe("read access (Phase 31 M3)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.doc(`reviews/${ORDER}`).set(review());
        await db.doc("reviews/order-2").set(review({ orderId: "order-2", createdAt: Date.now() - 1000 }));
        await db.doc("reviews/order-3").set(review({ orderId: "order-3", vendorId: "vendor-2" }));
        await db.doc("users/admin-1").set({ role: "admin" });
        await db.doc("users/vendor-owner-1").set({ role: "vendor" });
        await db.doc("users/driver-1").set({ role: "driver" });
      });
    });

    it("denies an unauthenticated get", async () => {
      await assertFails(testEnv.unauthenticatedContext().firestore().doc(`reviews/${ORDER}`).get());
    });

    it("denies an unauthenticated list and vendor query", async () => {
      const anon = testEnv.unauthenticatedContext().firestore();
      await assertFails(anon.collection("reviews").get());
      await assertFails(anon.collection("reviews").where("vendorId", "==", "vendor-1").get());
    });

    for (const [label, uid] of [
      ["a customer (the reviewer)", CUSTOMER],
      ["another customer", OTHER_CUSTOMER],
      ["a vendor owner", "vendor-owner-1"],
      ["a driver", "driver-1"],
      ["an admin", "admin-1"],
    ]) {
      it(`lets ${label} read a review`, async () => {
        await assertSucceeds(testEnv.authenticatedContext(uid).firestore().doc(`reviews/${ORDER}`).get());
      });
    }

    it("keeps the vendor review query (watchVendorReviews) working for a signed-in user", async () => {
      const query = testEnv
        .authenticatedContext(OTHER_CUSTOMER)
        .firestore()
        .collection("reviews")
        .where("vendorId", "==", "vendor-1")
        .orderBy("createdAt", "desc");
      const snapshot = await assertSucceeds(query.get());
      if (snapshot.size !== 2) throw new Error(`expected 2 vendor-1 reviews, got ${snapshot.size}`);
    });

    it("keeps the order's own review lookup (watchReviewForOrder) working", async () => {
      await assertSucceeds(testEnv.authenticatedContext(CUSTOMER).firestore().doc("reviews/order-2").get());
    });

    it("still denies updates and deletes, even for the reviewer and an admin", async () => {
      for (const uid of [CUSTOMER, "admin-1"]) {
        const db = testEnv.authenticatedContext(uid).firestore();
        await assertFails(db.doc(`reviews/${ORDER}`).update({ comment: "edited" }));
        await assertFails(db.doc(`reviews/${ORDER}`).delete());
      }
    });
  });

  describe("key and comment hardening (Phase 31 L3)", () => {
    it("denies unexpected fields", async () => {
      for (const extra of [{ approved: true }, { vendorRatingBonus: 5 }, { customerName: "X" }]) {
        await assertFails(reviewDoc(CUSTOMER).set(review(extra)));
      }
    });

    it("denies a non-string comment", async () => {
      for (const comment of [42, true, ["a"], { text: "a" }]) {
        await assertFails(reviewDoc(CUSTOMER).set(review({ comment })));
      }
    });

    it("denies a comment longer than 1000 characters", async () => {
      await assertFails(reviewDoc(CUSTOMER).set(review({ comment: "x".repeat(1001) })));
    });

    it("denies a non-integer createdAt", async () => {
      await assertFails(reviewDoc(CUSTOMER).set(review({ createdAt: "yesterday" })));
    });
  });

  describe("existing cross-checks still hold", () => {
    it("denies a second write (create-once)", async () => {
      await assertSucceeds(reviewDoc(CUSTOMER).set(review()));
      await assertFails(reviewDoc(CUSTOMER).set(review({ vendorRating: 1 })));
    });

    it("denies reviewing an order that isn't delivered", async () => {
      await seedOrder("delivering");
      await assertFails(reviewDoc(CUSTOMER).set(review()));
    });

    it("denies another customer, even claiming the right customerId", async () => {
      await assertFails(reviewDoc(OTHER_CUSTOMER).set(review()));
      await assertFails(reviewDoc(OTHER_CUSTOMER).set(review({ customerId: OTHER_CUSTOMER })));
    });

    it("denies a mismatched vendorId or driverId", async () => {
      await assertFails(reviewDoc(CUSTOMER).set(review({ vendorId: "vendor-2" })));
      await assertFails(reviewDoc(CUSTOMER).set(review({ driverId: "driver-2" })));
    });

    it("denies out-of-range or non-integer ratings", async () => {
      for (const bad of [{ vendorRating: 0 }, { vendorRating: 6 }, { driverRating: 4.5 }, { driverRating: "5" }]) {
        await assertFails(reviewDoc(CUSTOMER).set(review(bad)));
      }
    });

    it("denies deleting a review", async () => {
      await assertSucceeds(reviewDoc(CUSTOMER).set(review()));
      await assertFails(reviewDoc(CUSTOMER).delete());
    });
  });
});
