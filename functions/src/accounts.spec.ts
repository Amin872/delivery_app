import assert from "node:assert/strict";

import { AccountCleanupStore, deleteAccountData, onAuthUserDeleted } from "./accounts";

/** In-memory Firestore keyed by full document path, recording every
 * delete and every batch commit. Refs are the document paths. */
function fakeStore(paths: string[]) {
  const docs = new Set(paths);
  const deleted: string[] = [];
  const commits: number[] = [];
  const remove = (path: string) => {
    deleted.push(path);
    docs.delete(path);
  };
  const store: AccountCleanupStore = {
    doc: (path: string) => ({
      delete: async () => remove(path),
      collection: (id: string) => ({
        get: async () => {
          const prefix = `${path}/${id}/`;
          const children = [...docs].filter((p) => p.startsWith(prefix) && !p.slice(prefix.length).includes("/"));
          return { docs: children.map((ref) => ({ ref })) };
        },
      }),
    }),
    batch: () => {
      const pending: string[] = [];
      return {
        delete: (ref: never) => pending.push(ref as unknown as string),
        commit: async () => {
          commits.push(pending.length);
          pending.forEach(remove);
        },
      };
    },
  };
  return { store, docs, deleted, commits };
}

const HISTORY = [
  "orders/o1",
  "orders/o2",
  "reviews/o1",
  "vendors/u1",
  "vendors/u1/menuItems/m1",
  "drivers/u1",
  "orders/o1/driverLocation/current",
];

describe("deleteAccountData (Phase 31 M1)", () => {
  it("deletes users/{uid} and every address — nothing else", async () => {
    const { store, docs, deleted } = fakeStore([
      "users/u1",
      "users/u1/addresses/home",
      "users/u1/addresses/work",
      "users/u1/addresses/other",
      "users/u2",
      "users/u2/addresses/home",
      ...HISTORY,
    ]);

    const result = await deleteAccountData(store, "u1");

    assert.deepEqual(result, { addressesDeleted: 3 });
    assert.deepEqual(
      [...deleted].sort(),
      ["users/u1", "users/u1/addresses/home", "users/u1/addresses/other", "users/u1/addresses/work"]
    );
    // Orders, reviews, the vendor/driver records and other users stay.
    for (const path of [...HISTORY, "users/u2", "users/u2/addresses/home"]) {
      assert.ok(docs.has(path), path);
    }
  });

  it("deletes the addresses before the profile document", async () => {
    const { store, deleted } = fakeStore(["users/u1", "users/u1/addresses/home"]);
    await deleteAccountData(store, "u1");
    assert.deepEqual(deleted, ["users/u1/addresses/home", "users/u1"]);
  });

  it("is safe when the users doc is already missing", async () => {
    const { store, docs } = fakeStore(["users/u1/addresses/home", ...HISTORY]);
    assert.deepEqual(await deleteAccountData(store, "u1"), { addressesDeleted: 1 });
    assert.equal(docs.has("users/u1/addresses/home"), false);
    assert.equal(docs.size, HISTORY.length);
  });

  it("is safe with no addresses (no batch is committed)", async () => {
    const { store, deleted, commits } = fakeStore(["users/u1", ...HISTORY]);
    assert.deepEqual(await deleteAccountData(store, "u1"), { addressesDeleted: 0 });
    assert.deepEqual(deleted, ["users/u1"]);
    assert.deepEqual(commits, []);
  });

  it("is idempotent — a retry after a completed cleanup changes nothing", async () => {
    const { store, docs } = fakeStore(["users/u1", "users/u1/addresses/home", ...HISTORY]);
    await deleteAccountData(store, "u1");
    await deleteAccountData(store, "u1");
    assert.equal(docs.size, HISTORY.length);
  });

  it("splits large address lists into batches under Firestore's 500-write limit", async () => {
    const addresses = Array.from({ length: 450 }, (_, i) => `users/u1/addresses/a${i}`);
    const { store, docs, commits } = fakeStore(["users/u1", ...addresses]);
    assert.deepEqual(await deleteAccountData(store, "u1"), { addressesDeleted: 450 });
    assert.deepEqual(commits, [400, 50]);
    assert.equal(docs.size, 0);
  });

  it("refuses an invalid uid without deleting anything", async () => {
    const { store, deleted } = fakeStore(["users/u1", ...HISTORY]);
    for (const uid of ["", "u1/addresses/home", "../orders", "a/b"]) {
      await assert.rejects(() => deleteAccountData(store, uid));
    }
    assert.deepEqual(deleted, []);
  });

  it("is registered as a Firebase Auth user-delete trigger", () => {
    // The v1 endpoint resolves its resource from the project id, which the
    // Functions runtime provides; set one just for this read.
    const saved = process.env.GCLOUD_PROJECT;
    process.env.GCLOUD_PROJECT = "demo-project";
    try {
      const endpoint = (onAuthUserDeleted as unknown as {
        __endpoint: { platform: string; serviceAccountEmail?: string; eventTrigger: { eventType: string } };
      }).__endpoint;
      assert.equal(endpoint.platform, "gcfv1");
      assert.equal(endpoint.eventTrigger.eventType, "providers/firebase.auth/eventTypes/user.delete");
      assert.equal(endpoint.serviceAccountEmail, "637107525940-compute@developer.gserviceaccount.com");
    } finally {
      if (saved === undefined) delete process.env.GCLOUD_PROJECT;
      else process.env.GCLOUD_PROJECT = saved;
    }
  });
});
