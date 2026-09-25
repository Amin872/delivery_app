import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for orders/{orderId}'s `allow update` branches —
// specifically the vendor-ownership branch's field restriction added to
// close the gap an audit found: an owning vendor previously had no
// affectedKeys() restriction at all (unlike the customer-cancel branch
// right next to it), so could rewrite any field on their own order,
// including driverId/total/items/customerId. See firestore.rules' own
// comment on this `allow update` block for the full reasoning.
//
// Wrapped in one top-level describe() for the same root-suite-hook-ordering
// reason districts.rules.test.ts/neighborhoods.rules.test.ts document on
// their own describe() blocks.
describe("orders/{orderId} update rules", () => {
  let testEnv: RulesTestEnvironment;

  const ORDER_ID = "order-1";
  const VENDOR_ID = "vendor-1";
  const VENDOR_OWNER = "vendor-owner-1";
  const OTHER_VENDOR_OWNER = "vendor-owner-2";
  const CUSTOMER_ID = "customer-1";

  function baseOrder(status: string) {
    return {
      customerId: CUSTOMER_ID,
      vendorId: VENDOR_ID,
      driverId: null,
      status,
      items: [{ menuItemId: "item-1", name: "Item", quantity: 1, unitPrice: 10 }],
      total: 10,
      deliveryAddress: "Damascus, somewhere",
      createdAt: Date.now(),
      deliveryLatitude: 33.5,
      deliveryLongitude: 36.3,
    };
  }

  async function seedOrder(status: string) {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      const db = ctx.firestore();
      await db.collection("orders").doc(ORDER_ID).set(baseOrder(status));
      await db.collection("vendors").doc(VENDOR_ID).set({ ownerId: VENDOR_OWNER });
    });
  }

  function orderDoc(db: FirebaseFirestore.Firestore) {
    return db.collection("orders").doc(ORDER_ID);
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
  });

  describe("vendor owner — legitimate status-only updates (A)", () => {
    it("lets the owning vendor advance status (pending -> accepted)", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertSucceeds(orderDoc(vendorDb).update({ status: "accepted" }));
    });

    it("lets the owning vendor cancel a pre-dispatch order", async () => {
      await seedOrder("preparing");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertSucceeds(orderDoc(vendorDb).update({ status: "cancelled" }));
    });
  });

  describe("vendor owner — denied field writes (B-F)", () => {
    it("(B) denies modifying total, even alongside a status change", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(orderDoc(vendorDb).update({ status: "accepted", total: 999 }));
    });

    it("(C) denies modifying items", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(
        orderDoc(vendorDb).update({
          status: "accepted",
          items: [{ menuItemId: "item-2", name: "Swapped", quantity: 1, unitPrice: 1 }],
        })
      );
    });

    it("(D) denies modifying customerId", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(
        orderDoc(vendorDb).update({ status: "accepted", customerId: "someone-else" })
      );
    });

    it("(E) denies modifying delivery coordinates", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(
        orderDoc(vendorDb).update({
          status: "accepted",
          deliveryLatitude: 0,
          deliveryLongitude: 0,
        })
      );
    });

    it("(F) denies modifying driverId", async () => {
      await seedOrder("readyForPickup");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(
        orderDoc(vendorDb).update({ status: "readyForPickup", driverId: VENDOR_OWNER })
      );
    });

    it("denies a field-only write with no status change at all", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(orderDoc(vendorDb).update({ total: 1 }));
    });
  });

  describe("non-owning vendor (G)", () => {
    it("denies a vendor who does not own this order, even for a status-only write", async () => {
      await seedOrder("pending");
      const otherVendorDb = testEnv.authenticatedContext(OTHER_VENDOR_OWNER).firestore();
      await assertFails(orderDoc(otherVendorDb).update({ status: "accepted" }));
    });
  });

  describe("existing status/ownership restrictions still hold (H)", () => {
    it("still lets the owning customer cancel their own pending order", async () => {
      await seedOrder("pending");
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertSucceeds(orderDoc(customerDb).update({ status: "cancelled" }));
    });

    it("still denies the customer cancelling once no longer pending", async () => {
      await seedOrder("accepted");
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertFails(orderDoc(customerDb).update({ status: "cancelled" }));
    });

    it("still denies the customer setting any status other than cancelled", async () => {
      await seedOrder("pending");
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertFails(orderDoc(customerDb).update({ status: "accepted" }));
    });

    it("still denies an unrelated signed-in user from updating the order", async () => {
      await seedOrder("pending");
      const strangerDb = testEnv.authenticatedContext("stranger-1").firestore();
      await assertFails(orderDoc(strangerDb).update({ status: "accepted" }));
    });

    it("still denies an unauthenticated update", async () => {
      await seedOrder("pending");
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(orderDoc(anonDb).update({ status: "accepted" }));
    });

    it("still denies delete, even for the owning vendor", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(orderDoc(vendorDb).delete());
    });
  });

  // Orders are created only by the createOrder callable (Admin SDK); no
  // client-side create path exists at all.
  describe("client-side create is denied (I)", () => {
    beforeEach(async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        await ctx.firestore().collection("vendors").doc(VENDOR_ID).set({ ownerId: VENDOR_OWNER });
        await ctx.firestore().collection("users").doc(CUSTOMER_ID).set({ role: "customer" });
      });
    });

    it("denies a customer creating their own pending order directly", async () => {
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertFails(customerDb.collection("orders").add(baseOrder("pending")));
    });

    it("denies a customer forging an already-delivered order (with a driver)", async () => {
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertFails(
        orderDoc(customerDb).set({ ...baseOrder("delivered"), driverId: "driver-1", total: 1 })
      );
    });

    it("denies an unauthenticated create", async () => {
      const anonDb = testEnv.unauthenticatedContext().firestore();
      await assertFails(anonDb.collection("orders").add(baseOrder("pending")));
    });

    it("denies the vendor owner creating an order for their own store", async () => {
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertFails(vendorDb.collection("orders").add(baseOrder("pending")));
    });
  });

  describe("reads are unchanged (J)", () => {
    it("still lets the customer read their own order", async () => {
      await seedOrder("pending");
      const customerDb = testEnv.authenticatedContext(CUSTOMER_ID).firestore();
      await assertSucceeds(orderDoc(customerDb).get());
    });

    it("still lets the owning vendor read the order", async () => {
      await seedOrder("pending");
      const vendorDb = testEnv.authenticatedContext(VENDOR_OWNER).firestore();
      await assertSucceeds(orderDoc(vendorDb).get());
    });

    it("still denies an unrelated signed-in user from reading the order", async () => {
      await seedOrder("pending");
      const strangerDb = testEnv.authenticatedContext("stranger-1").firestore();
      await assertFails(orderDoc(strangerDb).get());
    });
  });

  // Status-lifecycle hardening: the vendor branch is limited to the vendor's
  // own stages (firestore.rules' isVendorStatusTransition), and no other
  // role has any direct write path to status, driver or price fields.
  describe("status lifecycle hardening (K)", () => {
    const DRIVER_ID = "driver-1";
    const ADMIN_ID = "admin-1";
    const ALL_STATUSES = [
      "pending",
      "accepted",
      "preparing",
      "readyForPickup",
      "driverAssigned",
      "pickedUp",
      "delivering",
      "delivered",
      "cancelled",
    ];
    // Exactly what vendor_dashboard_screen.dart offers.
    const VENDOR_ALLOWED = new Set([
      "pending->accepted",
      "accepted->preparing",
      "preparing->readyForPickup",
      "pending->cancelled",
      "accepted->cancelled",
      "preparing->cancelled",
    ]);

    // An order as createOrder writes it (Phase 21), with a driver assigned
    // from driverAssigned onwards.
    async function seedFullOrder(status: string) {
      const assigned = ["driverAssigned", "pickedUp", "delivering", "delivered"].includes(status);
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db
          .collection("orders")
          .doc(ORDER_ID)
          .set({
            ...baseOrder(status),
            driverId: assigned ? DRIVER_ID : null,
            subtotal: 10,
            deliveryFee: 5,
            total: 15,
            proofImageUrl: null,
            vendorName: "Vendor",
            pickupAddress: "Pickup St",
            pickupLatitude: 33.51,
            pickupLongitude: 36.27,
          });
        await db.collection("vendors").doc(VENDOR_ID).set({ ownerId: VENDOR_OWNER });
        await db.collection("users").doc(ADMIN_ID).set({ role: "admin" });
        await db.collection("users").doc(DRIVER_ID).set({ role: "driver" });
        await db.collection("users").doc(CUSTOMER_ID).set({ role: "customer" });
      });
    }

    function as(uid: string) {
      return orderDoc(testEnv.authenticatedContext(uid).firestore());
    }

    describe("vendor: every from -> to status pair", () => {
      for (const from of ALL_STATUSES) {
        for (const to of ALL_STATUSES) {
          if (from === to) continue;
          const allowed = VENDOR_ALLOWED.has(`${from}->${to}`);
          it(`${allowed ? "allows" : "denies"} ${from} -> ${to}`, async () => {
            await seedFullOrder(from);
            const write = as(VENDOR_OWNER).update({ status: to });
            await (allowed ? assertSucceeds(write) : assertFails(write));
          });
        }
      }

      it("denies an arbitrary, non-lifecycle status value", async () => {
        await seedFullOrder("pending");
        await assertFails(as(VENDOR_OWNER).update({ status: "refunded" }));
      });

      it("denies a non-string status value", async () => {
        await seedFullOrder("pending");
        await assertFails(as(VENDOR_OWNER).update({ status: 1 }));
      });
    });

    describe("vendor: a legal transition combined with any other field is denied", () => {
      const extraFields: Array<[string, Record<string, unknown>]> = [
        ["subtotal", { subtotal: 1 }],
        ["deliveryFee", { deliveryFee: 0 }],
        ["total", { total: 1 }],
        ["driverId", { driverId: DRIVER_ID }],
        ["vendorId", { vendorId: "vendor-2" }],
        ["customerId", { customerId: "someone-else" }],
        ["items", { items: [] }],
        ["createdAt", { createdAt: 1 }],
        ["proofImageUrl", { proofImageUrl: "https://example.com/fake.jpg" }],
        ["vendorName", { vendorName: "Renamed" }],
        ["pickupAddress", { pickupAddress: "Elsewhere" }],
        ["pickupLatitude/Longitude", { pickupLatitude: 0, pickupLongitude: 0 }],
        ["deliveryLatitude/Longitude", { deliveryLatitude: 0, deliveryLongitude: 0 }],
      ];
      for (const [label, extra] of extraFields) {
        it(`denies pending -> accepted together with ${label}`, async () => {
          await seedFullOrder("pending");
          await assertFails(as(VENDOR_OWNER).update({ status: "accepted", ...extra }));
        });
      }
    });

    describe("driver: no direct write path", () => {
      it("denies the assigned driver advancing status directly", async () => {
        await seedFullOrder("driverAssigned");
        await assertFails(as(DRIVER_ID).update({ status: "pickedUp" }));
      });

      it("denies the assigned driver marking the order delivered directly", async () => {
        await seedFullOrder("delivering");
        await assertFails(as(DRIVER_ID).update({ status: "delivered" }));
      });

      it("denies a driver claiming an unassigned order by setting driverId", async () => {
        await seedFullOrder("readyForPickup");
        await assertFails(as(DRIVER_ID).update({ driverId: DRIVER_ID }));
      });

      it("denies a driver claiming it with driverId + driverAssigned together", async () => {
        await seedFullOrder("readyForPickup");
        await assertFails(as(DRIVER_ID).update({ driverId: DRIVER_ID, status: "driverAssigned" }));
      });

      for (const [label, change] of [
        ["subtotal", { subtotal: 1 }],
        ["deliveryFee", { deliveryFee: 0 }],
        ["total", { total: 1 }],
        ["customerId", { customerId: DRIVER_ID }],
        ["vendorId", { vendorId: "vendor-2" }],
        ["items", { items: [] }],
        ["proofImageUrl", { proofImageUrl: "https://example.com/fake.jpg" }],
      ] as Array<[string, Record<string, unknown>]>) {
        it(`denies the assigned driver changing ${label}`, async () => {
          await seedFullOrder("delivering");
          await assertFails(as(DRIVER_ID).update(change));
        });
      }
    });

    describe("customer: cancellation only", () => {
      it("still allows cancelling their own pending order", async () => {
        await seedFullOrder("pending");
        await assertSucceeds(as(CUSTOMER_ID).update({ status: "cancelled" }));
      });

      for (const to of ["accepted", "preparing", "readyForPickup", "delivered"]) {
        it(`denies setting status ${to} directly`, async () => {
          await seedFullOrder("pending");
          await assertFails(as(CUSTOMER_ID).update({ status: to }));
        });
      }

      it("denies cancelling once the vendor has accepted", async () => {
        await seedFullOrder("accepted");
        await assertFails(as(CUSTOMER_ID).update({ status: "cancelled" }));
      });

      it("denies cancelling together with a price change", async () => {
        await seedFullOrder("pending");
        await assertFails(as(CUSTOMER_ID).update({ status: "cancelled", total: 0 }));
      });

      for (const [label, change] of [
        ["subtotal", { subtotal: 1 }],
        ["deliveryFee", { deliveryFee: 0 }],
        ["total", { total: 1 }],
        ["driverId", { driverId: CUSTOMER_ID }],
      ] as Array<[string, Record<string, unknown>]>) {
        it(`denies changing ${label} directly`, async () => {
          await seedFullOrder("pending");
          await assertFails(as(CUSTOMER_ID).update(change));
        });
      }

      it("denies un-cancelling a cancelled order", async () => {
        await seedFullOrder("cancelled");
        await assertFails(as(CUSTOMER_ID).update({ status: "pending" }));
      });
    });

    describe("admin: intervention stays callable-only", () => {
      // adminCancelOrder/adminReassignDriver (Admin SDK) are the admin path;
      // their status/driver logic is covered by functions/src/orders.spec.ts.
      it("denies an admin cancelling directly (must use adminCancelOrder)", async () => {
        await seedFullOrder("preparing");
        await assertFails(as(ADMIN_ID).update({ status: "cancelled" }));
      });

      it("denies an admin reassigning directly (must use adminReassignDriver)", async () => {
        await seedFullOrder("driverAssigned");
        await assertFails(as(ADMIN_ID).update({ driverId: "driver-2" }));
      });

      it("denies an admin changing prices directly", async () => {
        await seedFullOrder("pending");
        await assertFails(as(ADMIN_ID).update({ total: 1 }));
      });

      it("still lets an admin read any order", async () => {
        await seedFullOrder("delivering");
        await assertSucceeds(as(ADMIN_ID).get());
      });
    });
  });
  // Phase 24: the unclaimed readyForPickup queue is readable only by an
  // admin-approved driver. Exercised through the same list query the driver
  // app runs (FirestoreService.watchAvailableOrdersForDrivers), since that's
  // what Firestore has to prove against the rule.
  describe("driver queue approval (L)", () => {
    const QUEUE_DRIVER = "queue-driver";

    async function seedQueue(driverDoc: Record<string, unknown> | null, role = "driver") {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db.collection("orders").doc(ORDER_ID).set(baseOrder("readyForPickup"));
        await db.collection("vendors").doc(VENDOR_ID).set({ ownerId: VENDOR_OWNER });
        await db.collection("users").doc(QUEUE_DRIVER).set({ role });
        if (driverDoc) await db.collection("drivers").doc(QUEUE_DRIVER).set(driverDoc);
      });
    }

    function queueQuery() {
      return testEnv
        .authenticatedContext(QUEUE_DRIVER)
        .firestore()
        .collection("orders")
        .where("status", "==", "readyForPickup")
        .where("driverId", "==", null);
    }

    it("lets an approved driver run the available-orders query", async () => {
      await seedQueue({ isAvailable: true, approvalStatus: "approved" });
      const snap = await assertSucceeds(queueQuery().get());
      if (snap.size !== 1) throw new Error(`expected 1 queued order, got ${snap.size}`);
    });

    it("lets an approved driver read an unclaimed order by id", async () => {
      await seedQueue({ isAvailable: true, approvalStatus: "approved" });
      await assertSucceeds(orderDoc(testEnv.authenticatedContext(QUEUE_DRIVER).firestore()).get());
    });

    for (const approvalStatus of ["pending", "rejected"]) {
      it(`denies a ${approvalStatus} driver the available-orders query and the doc`, async () => {
        await seedQueue({ isAvailable: true, approvalStatus });
        await assertFails(queueQuery().get());
        await assertFails(orderDoc(testEnv.authenticatedContext(QUEUE_DRIVER).firestore()).get());
      });
    }

    it("denies a legacy driver whose doc has no approvalStatus", async () => {
      await seedQueue({ isAvailable: true });
      await assertFails(queueQuery().get());
    });

    it("denies a driver-role user with no drivers doc at all", async () => {
      await seedQueue(null);
      await assertFails(queueQuery().get());
    });

    it("still denies a non-driver, even with an approved-looking drivers doc", async () => {
      await seedQueue({ approvalStatus: "approved" }, "customer");
      await assertFails(queueQuery().get());
    });

    it("still lets a revoked driver read the order already assigned to them", async () => {
      await testEnv.withSecurityRulesDisabled(async (ctx) => {
        const db = ctx.firestore();
        await db
          .collection("orders")
          .doc(ORDER_ID)
          .set({ ...baseOrder("delivering"), driverId: QUEUE_DRIVER });
        await db.collection("vendors").doc(VENDOR_ID).set({ ownerId: VENDOR_OWNER });
        await db.collection("users").doc(QUEUE_DRIVER).set({ role: "driver" });
        await db.collection("drivers").doc(QUEUE_DRIVER).set({ approvalStatus: "rejected" });
      });
      await assertSucceeds(orderDoc(testEnv.authenticatedContext(QUEUE_DRIVER).firestore()).get());
    });
  });
});
