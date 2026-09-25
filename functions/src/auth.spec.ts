import assert from "node:assert/strict";

import {
  assertDriverAvailable,
  assertIsAdmin,
  assertIsApprovedDriver,
  assertIsCustomer,
  assertIsDriver,
  DocReader,
  isApprovedDriverDoc,
  isValidDocId,
  MAX_DOC_ID_LENGTH,
  requireDocId,
  UserRoleReader,
} from "./auth";

function fakeReader(role: string | undefined): UserRoleReader {
  return {
    collection: () => ({
      doc: () => ({
        get: async () => ({
          data: () => (role === undefined ? undefined : { role }),
        }),
      }),
    }),
  };
}

function assertPermissionDenied(error: unknown): true {
  assert.ok(error instanceof Error);
  assert.equal((error as { code?: string }).code, "permission-denied");
  return true;
}

describe("assertIsDriver", () => {
  it("resolves when the user has role 'driver'", async () => {
    await assert.doesNotReject(() => assertIsDriver(fakeReader("driver"), "uid-driver"));
  });

  it("rejects with permission-denied for a non-driver role", async () => {
    await assert.rejects(
      () => assertIsDriver(fakeReader("customer"), "uid-customer"),
      assertPermissionDenied
    );
  });

  it("rejects with permission-denied when the user document doesn't exist", async () => {
    await assert.rejects(
      () => assertIsDriver(fakeReader(undefined), "uid-missing"),
      assertPermissionDenied
    );
  });
});

describe("assertIsAdmin", () => {
  it("resolves when the user has role 'admin'", async () => {
    await assert.doesNotReject(() => assertIsAdmin(fakeReader("admin"), "uid-admin"));
  });

  it("rejects with permission-denied for a non-admin role", async () => {
    await assert.rejects(
      () => assertIsAdmin(fakeReader("vendor"), "uid-vendor"),
      assertPermissionDenied
    );
  });

  it("rejects with permission-denied when the user document doesn't exist", async () => {
    await assert.rejects(
      () => assertIsAdmin(fakeReader(undefined), "uid-missing"),
      assertPermissionDenied
    );
  });
});

describe("assertIsCustomer", () => {
  it("resolves when the user has role 'customer'", async () => {
    await assert.doesNotReject(() => assertIsCustomer(fakeReader("customer"), "uid-customer"));
  });

  for (const role of ["driver", "vendor", "admin"]) {
    it(`rejects with permission-denied for role '${role}'`, async () => {
      await assert.rejects(
        () => assertIsCustomer(fakeReader(role), `uid-${role}`),
        assertPermissionDenied
      );
    });
  }

  it("rejects with permission-denied when the user document doesn't exist", async () => {
    await assert.rejects(
      () => assertIsCustomer(fakeReader(undefined), "uid-missing"),
      assertPermissionDenied
    );
  });
});

// Serves users/{uid} and drivers/{uid} separately, unlike fakeReader above.
function fakeDocReader(docs: { users?: Record<string, unknown>; drivers?: Record<string, unknown> }): DocReader {
  return {
    collection: (path: string) => ({
      doc: () => ({
        get: async () => ({ data: () => docs[path as "users" | "drivers"] }),
      }),
    }),
  };
}

describe("assertIsApprovedDriver", () => {
  it("resolves for an approved driver", async () => {
    await assert.doesNotReject(() =>
      assertIsApprovedDriver(
        fakeDocReader({ users: { role: "driver" }, drivers: { approvalStatus: "approved" } }),
        "uid-driver"
      )
    );
  });

  for (const approvalStatus of ["pending", "rejected", "unknown-value"]) {
    it(`rejects a driver whose approvalStatus is '${approvalStatus}'`, async () => {
      await assert.rejects(
        () =>
          assertIsApprovedDriver(
            fakeDocReader({ users: { role: "driver" }, drivers: { approvalStatus } }),
            "uid-driver"
          ),
        assertPermissionDenied
      );
    });
  }

  it("rejects a driver whose doc has no approvalStatus field (legacy)", async () => {
    await assert.rejects(
      () => assertIsApprovedDriver(fakeDocReader({ users: { role: "driver" }, drivers: { isAvailable: true } }), "uid"),
      assertPermissionDenied
    );
  });

  it("rejects a driver with no drivers doc at all", async () => {
    await assert.rejects(
      () => assertIsApprovedDriver(fakeDocReader({ users: { role: "driver" } }), "uid"),
      assertPermissionDenied
    );
  });

  it("rejects a non-driver role even if a drivers doc says approved", async () => {
    await assert.rejects(
      () =>
        assertIsApprovedDriver(
          fakeDocReader({ users: { role: "customer" }, drivers: { approvalStatus: "approved" } }),
          "uid"
        ),
      assertPermissionDenied
    );
  });

  it("leaves assertIsDriver unchanged: role-only, approval not considered", async () => {
    await assert.doesNotReject(() => assertIsDriver(fakeReader("driver"), "uid-driver"));
  });
});

describe("isApprovedDriverDoc", () => {
  it("is true only for an explicit 'approved'", () => {
    assert.equal(isApprovedDriverDoc({ approvalStatus: "approved" }), true);
    for (const value of ["pending", "rejected", "APPROVED", undefined, null, true]) {
      assert.equal(isApprovedDriverDoc({ approvalStatus: value }), false, String(value));
    }
    assert.equal(isApprovedDriverDoc(undefined), false);
  });
});

// acceptDelivery's full precondition chain: assertIsApprovedDriver (role +
// approval) resolves with the drivers doc it read, then assertDriverAvailable.
async function acceptPreconditions(docs: {
  users?: Record<string, unknown>;
  drivers?: Record<string, unknown>;
}): Promise<void> {
  const driver = await assertIsApprovedDriver(fakeDocReader(docs), "uid-driver");
  assertDriverAvailable(driver);
}

function assertDriverUnavailable(error: unknown): true {
  assert.ok(error instanceof Error);
  assert.equal((error as { code?: string }).code, "failed-precondition");
  assert.equal((error as { details?: { reason?: string } }).details?.reason, "driver-unavailable");
  return true;
}

describe("accept preconditions: approval + availability (Phase 25)", () => {
  it("an approved, available driver passes", async () => {
    await assert.doesNotReject(() =>
      acceptPreconditions({
        users: { role: "driver" },
        drivers: { approvalStatus: "approved", isAvailable: true },
      })
    );
  });

  it("assertIsApprovedDriver resolves with the drivers doc it read", async () => {
    const driver = await assertIsApprovedDriver(
      fakeDocReader({ users: { role: "driver" }, drivers: { approvalStatus: "approved", isAvailable: true } }),
      "uid-driver"
    );
    assert.deepEqual(driver, { approvalStatus: "approved", isAvailable: true });
  });

  it("an approved but unavailable driver is rejected with reason driver-unavailable", async () => {
    await assert.rejects(
      () =>
        acceptPreconditions({
          users: { role: "driver" },
          drivers: { approvalStatus: "approved", isAvailable: false },
        }),
      assertDriverUnavailable
    );
  });

  for (const isAvailable of [undefined, null, "true", 1]) {
    it(`treats isAvailable ${JSON.stringify(isAvailable)} as offline`, async () => {
      const drivers: Record<string, unknown> = { approvalStatus: "approved" };
      if (isAvailable !== undefined) drivers.isAvailable = isAvailable;
      await assert.rejects(
        () => acceptPreconditions({ users: { role: "driver" }, drivers }),
        assertDriverUnavailable
      );
    });
  }

  for (const approvalStatus of ["pending", "rejected"]) {
    it(`a ${approvalStatus} driver is still rejected by approval, even when available`, async () => {
      await assert.rejects(
        () =>
          acceptPreconditions({
            users: { role: "driver" },
            drivers: { approvalStatus, isAvailable: true },
          }),
        assertPermissionDenied
      );
    });
  }
});

// Phase 31 (C1/M4): every callable document ID is ONE Firestore document
// ID, never a path the Admin SDK would follow into another document.
export const VALID_DOC_IDS = ["o1", "Xy3kP9aQ2mN7bR4tL8vW", "a".repeat(MAX_DOC_ID_LENGTH), "falafel_wrap-2", "طلب-1"];
export const INVALID_DOC_IDS: unknown[] = [
  "",
  "   ",
  undefined,
  null,
  42,
  true,
  {},
  ["o1"],
  "O/driverLocation/X",
  "/o1",
  "o1/",
  "a/b",
  "..\\o1",
  "o1\\x",
  ".",
  "..",
  "__name__",
  "__o1__",
  "o1\nx",
  "o1\u0000",
  "a".repeat(MAX_DOC_ID_LENGTH + 1),
];

describe("isValidDocId / requireDocId (Phase 31)", () => {
  it("accepts ordinary document IDs, up to the maximum length", () => {
    for (const id of VALID_DOC_IDS) {
      assert.equal(isValidDocId(id), true, id);
      assert.equal(requireDocId(id, "orderId"), id);
    }
  });

  it("rejects non-strings, blanks, path separators, traversal, reserved, control chars and over-long IDs", () => {
    for (const id of INVALID_DOC_IDS) {
      assert.equal(isValidDocId(id), false, JSON.stringify(id));
    }
  });

  it("requireDocId throws a controlled invalid-argument error naming the field", () => {
    for (const id of INVALID_DOC_IDS) {
      assert.throws(
        () => requireDocId(id, "driverId"),
        (error: unknown) => {
          assert.ok(error instanceof Error);
          assert.equal((error as { code?: string }).code, "invalid-argument");
          assert.match((error as Error).message, /^driverId /);
          return true;
        },
        JSON.stringify(id)
      );
    }
  });
});
