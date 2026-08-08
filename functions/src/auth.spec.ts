import assert from "node:assert/strict";

import { assertIsDriver, UserRoleReader } from "./auth";

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
