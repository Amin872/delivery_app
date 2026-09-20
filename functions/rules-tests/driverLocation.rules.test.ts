import * as fs from "fs";
import * as path from "path";
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from "@firebase/rules-unit-testing";
import type { RulesTestEnvironment } from "@firebase/rules-unit-testing";

// Security-rule coverage for the Driver Live Location redesign
// (orders/{orderId}/driverLocation/{locationId}) and the narrowed
// drivers/{driverId} general read. Runs against a real Firestore emulator
// via `firebase emulators:exec` (see functions/package.json's test:rules
// script) — fake_cloud_firestore (used by the Dart unit tests) has no rules
// engine, so this is the only way to verify who can actually read/write
// these paths.

let testEnv: RulesTestEnvironment;

const ORDER_ID = "order-1";

async function seedOrder(status: string, driverId: string | null = "driver-1") {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection("orders").doc(ORDER_ID).set({
      customerId: "customer-1",
      vendorId: "vendor-1",
      driverId,
      status,
      items: [],
      total: 10,
      deliveryAddress: "addr",
      createdAt: Date.now(),
    });
    await db.collection("vendors").doc("vendor-1").set({ ownerId: "vendor-owner-1" });
    await db.collection("users").doc("admin-1").set({ role: "admin" });
  });
}

function locationDoc(db: FirebaseFirestore.Firestore) {
  return db.collection("orders").doc(ORDER_ID).collection("driverLocation").doc("current");
}

const samplePosition = { latitude: 33.5, longitude: 36.3, updatedAt: Date.now() };

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: "delivery-app-rules-test",
    firestore: {
      // Resolved from process.cwd() rather than __dirname/import.meta.url —
      // this file loads inconsistently as CJS vs ESM depending on the Node
      // version running it, and process.cwd() is reliable either way since
      // `npm run test:rules` always runs with functions/ as the cwd.
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

describe("orders/{orderId}/driverLocation/{locationId} writes", () => {
  it("lets the assigned driver publish while the order is pickedUp", async () => {
    await seedOrder("pickedUp");
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertSucceeds(locationDoc(driverDb).set(samplePosition));
  });

  it("lets the assigned driver publish while the order is delivering", async () => {
    await seedOrder("delivering");
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertSucceeds(locationDoc(driverDb).set(samplePosition));
  });

  it("denies a driver who is not assigned to this order", async () => {
    await seedOrder("pickedUp", "driver-1");
    const otherDriverDb = testEnv.authenticatedContext("driver-2").firestore();
    await assertFails(locationDoc(otherDriverDb).set(samplePosition));
  });

  it("denies publishing before a driver has been assigned", async () => {
    await seedOrder("readyForPickup", null);
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertFails(locationDoc(driverDb).set(samplePosition));
  });

  it("denies publishing once the order is delivered", async () => {
    await seedOrder("delivered");
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertFails(locationDoc(driverDb).set(samplePosition));
  });

  it("denies publishing while the order is still pending", async () => {
    await seedOrder("pending");
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertFails(locationDoc(driverDb).set(samplePosition));
  });

  it("denies deleting the location doc, even for the assigned driver", async () => {
    await seedOrder("delivering");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await locationDoc(ctx.firestore()).set(samplePosition);
    });
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertFails(locationDoc(driverDb).delete());
  });

  it("denies an unauthenticated write", async () => {
    await seedOrder("pickedUp");
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(locationDoc(anonDb).set(samplePosition));
  });
});

describe("orders/{orderId}/driverLocation/{locationId} reads", () => {
  beforeEach(async () => {
    await seedOrder("delivering");
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await locationDoc(ctx.firestore()).set(samplePosition);
    });
  });

  it("lets the owning customer read it", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertSucceeds(locationDoc(customerDb).get());
  });

  it("lets the assigned driver read it", async () => {
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertSucceeds(locationDoc(driverDb).get());
  });

  it("lets the owning vendor read it", async () => {
    const vendorDb = testEnv.authenticatedContext("vendor-owner-1").firestore();
    await assertSucceeds(locationDoc(vendorDb).get());
  });

  it("lets an admin read it", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(locationDoc(adminDb).get());
  });

  it("denies an unrelated signed-in user from reading it", async () => {
    const strangerDb = testEnv.authenticatedContext("stranger-1").firestore();
    await assertFails(locationDoc(strangerDb).get());
  });

  it("denies an unauthenticated read", async () => {
    const anonDb = testEnv.unauthenticatedContext().firestore();
    await assertFails(locationDoc(anonDb).get());
  });
});

describe("drivers/{driverId} general read (narrowed off the broad isSignedIn() shape)", () => {
  beforeEach(async () => {
    await testEnv.withSecurityRulesDisabled(async (ctx) => {
      await ctx.firestore().collection("drivers").doc("driver-1").set({ isAvailable: true });
      await ctx.firestore().collection("users").doc("admin-1").set({ role: "admin" });
    });
  });

  it("lets a driver read their own doc", async () => {
    const driverDb = testEnv.authenticatedContext("driver-1").firestore();
    await assertSucceeds(driverDb.collection("drivers").doc("driver-1").get());
  });

  it("lets an admin read any driver doc", async () => {
    const adminDb = testEnv.authenticatedContext("admin-1").firestore();
    await assertSucceeds(adminDb.collection("drivers").doc("driver-1").get());
  });

  it("denies an unrelated signed-in customer from reading a driver doc", async () => {
    const customerDb = testEnv.authenticatedContext("customer-1").firestore();
    await assertFails(customerDb.collection("drivers").doc("driver-1").get());
  });
});
