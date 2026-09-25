import assert from "node:assert/strict";

import {
  assertAdminCancellable,
  assertAdminReassignable,
  assertApprovedReassignmentTarget,
  assertValidReassignmentTarget,
  acceptDelivery,
  adminCancelOrder,
  adminReassignDriver,
  advanceDelivery,
  defaultStorageBucket,
  MAX_PROOF_IMAGE_URL_LENGTH,
  menuItemOrderCountIncrements,
  proofObjectPath,
  validateProofImageUrl,
  nextDeliveryStatus,
  reassignmentUpdate,
} from "./orders";
import { INVALID_DOC_IDS } from "./auth.spec";

function assertHttpsError(code: string) {
  return (error: unknown): true => {
    assert.ok(error instanceof Error);
    assert.equal((error as { code?: string }).code, code);
    return true;
  };
}

describe("nextDeliveryStatus", () => {
  it("advances driverAssigned to pickedUp for the assigned driver", () => {
    const order = { status: "driverAssigned", driverId: "driver-1" };
    assert.equal(nextDeliveryStatus(order, "driver-1"), "pickedUp");
  });

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

  for (const status of ["driverAssigned", "pickedUp", "delivering", "delivered", "cancelled"]) {
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

  for (const status of ["readyForPickup", "driverAssigned", "pickedUp"]) {
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

describe("reassignmentUpdate", () => {
  it("readyForPickup + new driver: sets driverId AND advances status to driverAssigned", () => {
    const update = reassignmentUpdate("readyForPickup", "new-driver-1");
    assert.deepEqual(update, { driverId: "new-driver-1", status: "driverAssigned" });
  });

  it("driverAssigned: changes driverId only, status is not included in the update", () => {
    const update = reassignmentUpdate("driverAssigned", "new-driver-1");
    assert.deepEqual(update, { driverId: "new-driver-1" });
    assert.ok(!("status" in update));
  });

  it("pickedUp: changes driverId only, status is not included in the update", () => {
    const update = reassignmentUpdate("pickedUp", "new-driver-1");
    assert.deepEqual(update, { driverId: "new-driver-1" });
    assert.ok(!("status" in update));
  });
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

describe("assertApprovedReassignmentTarget", () => {
  it("allows an approved target driver", () => {
    assert.doesNotThrow(() => assertApprovedReassignmentTarget({ approvalStatus: "approved" }));
  });

  for (const approvalStatus of ["pending", "rejected", "superApproved", undefined, null]) {
    it(`throws failed-precondition for a target with approvalStatus ${String(approvalStatus)}`, () => {
      assert.throws(
        () => assertApprovedReassignmentTarget({ approvalStatus }),
        assertHttpsError("failed-precondition")
      );
    });
  }

  it("throws failed-precondition when the target has no drivers doc", () => {
    assert.throws(
      () => assertApprovedReassignmentTarget(undefined),
      assertHttpsError("failed-precondition")
    );
  });
});

describe("advanceDelivery stays approval-independent", () => {
  // nextDeliveryStatus is advanceDelivery's whole decision; it takes only the
  // order and the caller, never approval state, so a driver whose approval
  // is revoked mid-delivery can still finish the order they hold.
  for (const [from, to] of [
    ["driverAssigned", "pickedUp"],
    ["pickedUp", "delivering"],
    ["delivering", "delivered"],
  ]) {
    it(`still advances ${from} -> ${to} for the assigned driver`, () => {
      assert.equal(nextDeliveryStatus({ status: from, driverId: "driver-1" }, "driver-1"), to);
    });
  }
});

describe("advanceDelivery stays availability-independent (Phase 25)", () => {
  // Availability is checked only by acceptDelivery (assertDriverAvailable).
  // advanceDelivery's decision (nextDeliveryStatus) sees only the order and
  // the caller, so a driver who goes offline mid-delivery can still finish.
  it("an offline driver can still move their own order from delivering to delivered", () => {
    const order = { status: "delivering", driverId: "driver-1" };
    assert.equal(nextDeliveryStatus(order, "driver-1"), "delivered");
  });
});

// Phase 31 (C1/M4): each order/driver callable validates its document IDs
// before any Firestore access (including the caller's role lookup), with
// the same invalid-argument code it has always used for a missing ID.
describe("callable document-ID validation (Phase 31)", () => {
  type Callable = { run: (request: never) => unknown };

  function call(fn: Callable, data: Record<string, unknown>) {
    const request = { data, auth: { uid: "caller-1", token: {} }, rawRequest: {}, acceptsStreaming: false };
    return async () => fn.run(request as never);
  }

  const cases: Array<[string, Callable, (id: unknown) => Record<string, unknown>]> = [
    ["acceptDelivery orderId", acceptDelivery, (id) => ({ orderId: id })],
    ["advanceDelivery orderId", advanceDelivery, (id) => ({ orderId: id })],
    ["adminCancelOrder orderId", adminCancelOrder, (id) => ({ orderId: id })],
    ["adminReassignDriver orderId", adminReassignDriver, (id) => ({ orderId: id, driverId: "driver-1" })],
    ["adminReassignDriver driverId", adminReassignDriver, (id) => ({ orderId: "order-1", driverId: id })],
  ];

  for (const [label, fn, data] of cases) {
    it(`${label}: rejects non-string, empty, path-like and over-long IDs with invalid-argument`, async () => {
      for (const id of INVALID_DOC_IDS) {
        await assert.rejects(call(fn, data(id)), assertHttpsError("invalid-argument"), JSON.stringify(id));
      }
    });
  }

  it("the injected driverLocation path is rejected by every order callable", async () => {
    const injected = "O/driverLocation/X";
    for (const [, fn, data] of cases) {
      await assert.rejects(call(fn, data(injected)), assertHttpsError("invalid-argument"));
    }
  });
});

// Phase 31 (H3): advanceDelivery stores proofImageUrl only when it is THIS
// order's own proof object — never an arbitrary or external URL.
describe("validateProofImageUrl (Phase 31)", () => {
  const BUCKET = "delivery-app-syria-2026.firebasestorage.app";
  const ORDER = "order-1";
  const opts = { bucket: BUCKET };

  // Exactly the shape getDownloadURL() returns for orderProofs/order-1/proof.jpg.
  const url = (object = `orderProofs%2F${ORDER}%2Fproof.jpg`, bucket = BUCKET, query = "?alt=media&token=1a2b-3c4d") =>
    `https://firebasestorage.googleapis.com/v0/b/${bucket}/o/${object}${query}`;

  const rejects = (value: unknown, options: Parameters<typeof validateProofImageUrl>[2] = opts) =>
    assert.throws(() => validateProofImageUrl(value, ORDER, options), assertHttpsError("invalid-argument"), String(value));

  describe("accepted", () => {
    it("this order's download URL, returned unchanged (the value the apps render)", () => {
      assert.equal(validateProofImageUrl(url(), ORDER, opts), url());
    });

    it("a download URL without a token", () => {
      assert.equal(validateProofImageUrl(url(undefined, undefined, "?alt=media"), ORDER, opts), url(undefined, undefined, "?alt=media"));
    });

    it("the canonical object path", () => {
      assert.equal(proofObjectPath(ORDER), "orderProofs/order-1/proof.jpg");
      assert.equal(validateProofImageUrl("orderProofs/order-1/proof.jpg", ORDER, opts), "orderProofs/order-1/proof.jpg");
    });

    it("no proof (undefined, null, empty string) stays optional → null", () => {
      for (const value of [undefined, null, ""]) {
        assert.equal(validateProofImageUrl(value, ORDER, opts), null);
      }
    });

    it("a local Storage emulator URL only when the emulator host is allowed", () => {
      const emulator = `http://10.0.2.2:9199/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media&token=t`;
      assert.equal(validateProofImageUrl(emulator, ORDER, { bucket: BUCKET, allowEmulatorHost: true }), emulator);
      rejects(emulator);
      // Even then, the bucket and object path must be exact.
      rejects(emulator.replace("order-1", "order-2"), { bucket: BUCKET, allowEmulatorHost: true });
    });
  });

  describe("rejected", () => {
    it("another order's proof (URL or path)", () => {
      rejects(url("orderProofs%2Forder-2%2Fproof.jpg"));
      rejects("orderProofs/order-2/proof.jpg");
    });

    it("another file name, folder or object", () => {
      rejects(url(`orderProofs%2F${ORDER}%2Fproof.png`));
      rejects(url(`orderProofs%2F${ORDER}%2Fother.jpg`));
      rejects(url(`vendorImages%2Fvendor-1%2Fstorefront.jpg`));
      rejects(url(`promotions%2Fp1%2Fmedia.jpg`));
      rejects(`orderProofs/${ORDER}/proof.jpg.exe`);
      rejects(`/orderProofs/${ORDER}/proof.jpg`);
    });

    it("the wrong bucket, or no known bucket", () => {
      rejects(url(undefined, "evil-bucket.appspot.com"));
      rejects(url(undefined, "delivery-app-syria-2026.appspot.com"));
      rejects(url(), { bucket: null });
    });

    it("external hosts and arbitrary URLs", () => {
      for (const value of [
        "https://evil.example.com/pixel.gif",
        `https://evil.example.com/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`,
        `https://firebasestorage.googleapis.com.evil.com/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`,
        `https://storage.googleapis.com/${BUCKET}/orderProofs/${ORDER}/proof.jpg`,
        `http://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`,
        `https://firebasestorage.googleapis.com:8443/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`,
        `https://user:pw@firebasestorage.googleapis.com/v0/b/${BUCKET}/o/orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`,
        `gs://${BUCKET}/orderProofs/${ORDER}/proof.jpg`,
        "javascript:alert(1)",
        "data:image/png;base64,AAAA",
        "not a url",
        "proof.jpg",
      ]) {
        rejects(value);
      }
    });

    it("extra query parameters, a fragment, or a missing/wrong alt", () => {
      rejects(url(undefined, undefined, "?alt=media&token=t&redirect=https://evil.example.com"));
      rejects(url(undefined, undefined, "?alt=media&token=t#x"));
      rejects(url(undefined, undefined, "?token=t"));
      rejects(url(undefined, undefined, "?alt=json&token=t"));
      rejects(url(undefined, undefined, "?alt=media&alt=media&token=t"));
      rejects(url(undefined, undefined, "?alt=media&token=a&token=b"));
    });

    it("path traversal and encoding tricks", () => {
      rejects(`https://firebasestorage.googleapis.com/v0/b/${BUCKET}/o/x/../orderProofs%2F${ORDER}%2Fproof.jpg?alt=media`);
      rejects(url(`orderProofs%2Forder-2%2F..%2F${ORDER}%2Fproof.jpg`));
      rejects(url(`orderProofs%252F${ORDER}%252Fproof.jpg`));
      rejects(url(`orderProofs/${ORDER}/proof.jpg`));
      rejects(url(`%E0%A4%A`));
      rejects(`orderProofs/../orderProofs/${ORDER}/proof.jpg`);
    });

    it("non-strings and over-long values", () => {
      for (const value of [42, true, {}, ["x"]]) {
        rejects(value);
      }
      const padded = url(undefined, undefined, `?alt=media&token=${"a".repeat(MAX_PROOF_IMAGE_URL_LENGTH)}`);
      rejects(padded);
    });
  });

  describe("defaultStorageBucket", () => {
    const saved = process.env.FIREBASE_CONFIG;
    afterEach(() => {
      if (saved === undefined) delete process.env.FIREBASE_CONFIG;
      else process.env.FIREBASE_CONFIG = saved;
    });

    it("reads storageBucket from FIREBASE_CONFIG, and is null when absent or malformed", () => {
      process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "p", storageBucket: BUCKET });
      assert.equal(defaultStorageBucket(), BUCKET);
      process.env.FIREBASE_CONFIG = JSON.stringify({ projectId: "p" });
      assert.equal(defaultStorageBucket(), null);
      process.env.FIREBASE_CONFIG = "{not json";
      assert.equal(defaultStorageBucket(), null);
      delete process.env.FIREBASE_CONFIG;
      assert.equal(defaultStorageBucket(), null);
    });
  });

  describe("advanceDelivery callable", () => {
    const run = (data: Record<string, unknown>) => {
      const request = { data, auth: { uid: "driver-1", token: {} }, rawRequest: {}, acceptsStreaming: false };
      return async () => advanceDelivery.run(request as never);
    };

    it("rejects an invalid proof before touching the order (no Firestore access happens)", async () => {
      for (const proofImageUrl of [
        "https://evil.example.com/pixel.gif",
        url("orderProofs%2Forder-2%2Fproof.jpg"),
        42,
      ]) {
        await assert.rejects(run({ orderId: ORDER, proofImageUrl }), assertHttpsError("invalid-argument"));
      }
    });
  });
});
