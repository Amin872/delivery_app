import assert from "node:assert/strict";

import { nextDeliveryStatus } from "./orders";

function assertHttpsError(code: string) {
  return (error: unknown): true => {
    assert.ok(error instanceof Error);
    assert.equal((error as { code?: string }).code, code);
    return true;
  };
}

describe("nextDeliveryStatus", () => {
  it("advances pickedUp to delivering for the assigned driver", () => {
    const order = { status: "pickedUp", driverId: "driver-1" };
    assert.equal(nextDeliveryStatus(order, "driver-1"), "delivering");
  });

  it("advances delivering to delivered for the assigned driver", () => {
    const order = { status: "delivering", driverId: "driver-1" };
    assert.equal(nextDeliveryStatus(order, "driver-1"), "delivered");
  });

  it("throws not-found when the order doesn't exist", () => {
    assert.throws(() => nextDeliveryStatus(undefined, "driver-1"), assertHttpsError("not-found"));
  });

  it("throws permission-denied for a driver not assigned to the order", () => {
    const order = { status: "pickedUp", driverId: "driver-1" };
    assert.throws(
      () => nextDeliveryStatus(order, "driver-2"),
      assertHttpsError("permission-denied")
    );
  });

  it("throws failed-precondition for a status with no next step", () => {
    const order = { status: "delivered", driverId: "driver-1" };
    assert.throws(
      () => nextDeliveryStatus(order, "driver-1"),
      assertHttpsError("failed-precondition")
    );
  });

  it("throws failed-precondition for an order not yet picked up", () => {
    const order = { status: "readyForPickup", driverId: "driver-1" };
    assert.throws(
      () => nextDeliveryStatus(order, "driver-1"),
      assertHttpsError("failed-precondition")
    );
  });
});
