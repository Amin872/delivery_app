import assert from "node:assert/strict";

import {
  assertAdminCancellable,
  assertAdminReassignable,
  assertValidReassignmentTarget,
  menuItemOrderCountIncrements,
  nextDeliveryStatus,
} from "./orders";

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

describe("menuItemOrderCountIncrements", () => {
  it("maps each item to its quantity, keyed by menuItemId", () => {
    const order = {
      items: [
        { menuItemId: "item-1", quantity: 2 },
        { menuItemId: "item-2", quantity: 1 },
      ],
    };
    assert.deepEqual(menuItemOrderCountIncrements(order), [
      { menuItemId: "item-1", incrementBy: 2 },
      { menuItemId: "item-2", incrementBy: 1 },
    ]);
  });

  it("defaults incrementBy to 1 when quantity is missing", () => {
    const order = { items: [{ menuItemId: "item-1" }] };
    assert.deepEqual(menuItemOrderCountIncrements(order), [
      { menuItemId: "item-1", incrementBy: 1 },
    ]);
  });

  it("skips items with no menuItemId", () => {
    const order = { items: [{ quantity: 3 }, { menuItemId: "item-1", quantity: 1 }] };
    assert.deepEqual(menuItemOrderCountIncrements(order), [
      { menuItemId: "item-1", incrementBy: 1 },
    ]);
  });

  it("returns an empty array when items is missing or empty", () => {
    assert.deepEqual(menuItemOrderCountIncrements({}), []);
    assert.deepEqual(menuItemOrderCountIncrements({ items: [] }), []);
  });
});

describe("assertAdminCancellable", () => {
  it("throws not-found when the order doesn't exist", () => {
    assert.throws(() => assertAdminCancellable(undefined), assertHttpsError("not-found"));
  });

  for (const status of ["pending", "accepted", "preparing", "readyForPickup"]) {
    it(`allows cancelling an order with status '${status}'`, () => {
      assert.doesNotThrow(() => assertAdminCancellable({ status }));
    });
  }

  for (const status of ["pickedUp", "delivering", "delivered", "cancelled"]) {
    it(`throws failed-precondition for status '${status}'`, () => {
      assert.throws(
        () => assertAdminCancellable({ status }),
        assertHttpsError("failed-precondition")
      );
    });
  }
});

describe("assertAdminReassignable", () => {
  it("throws not-found when the order doesn't exist", () => {
    assert.throws(() => assertAdminReassignable(undefined), assertHttpsError("not-found"));
  });

  for (const status of ["readyForPickup", "pickedUp"]) {
    it(`allows reassigning an order with status '${status}'`, () => {
      assert.doesNotThrow(() => assertAdminReassignable({ status }));
    });
  }

  for (const status of ["pending", "accepted", "preparing", "delivering", "delivered", "cancelled"]) {
    it(`throws failed-precondition for status '${status}'`, () => {
      assert.throws(
        () => assertAdminReassignable({ status }),
        assertHttpsError("failed-precondition")
      );
    });
  }
});

describe("assertValidReassignmentTarget", () => {
  it("throws not-found when the target user doesn't exist", () => {
    assert.throws(
      () => assertValidReassignmentTarget(undefined),
      assertHttpsError("not-found")
    );
  });

  it("throws failed-precondition when the target user isn't a driver", () => {
    assert.throws(
      () => assertValidReassignmentTarget({ role: "customer" }),
      assertHttpsError("failed-precondition")
    );
  });

  it("allows a target user with role 'driver'", () => {
    assert.doesNotThrow(() => assertValidReassignmentTarget({ role: "driver" }));
  });
});
