import assert from "node:assert/strict";

import type { DocReader } from "./auth";
import { INVALID_DOC_IDS, VALID_DOC_IDS } from "./auth.spec";
import {
  contactTargetUid,
  ContactTarget,
  getOrderContact,
  parseContactRequest,
  phoneFromUser,
  resolveOrderContact,
} from "./contacts";

const CUSTOMER = "customer-1";
const DRIVER = "driver-1";
const VENDOR_OWNER = "vendor-owner-1";

function order(status: string, driverId: string | null = DRIVER): Record<string, unknown> {
  return { customerId: CUSTOMER, vendorId: "vendor-1", driverId, status, total: 10 };
}

function assertReason(code: string, reason: string) {
  return (error: unknown): true => {
    assert.ok(error instanceof Error);
    assert.equal((error as { code?: string }).code, code);
    assert.equal((error as { details?: { reason?: string } }).details?.reason, reason);
    return true;
  };
}

const notAuthorized = assertReason("permission-denied", "contact-not-authorized");

function uid(callerUid: string, target: ContactTarget, o: Record<string, unknown> | undefined) {
  return contactTargetUid({ callerUid, target, order: o, vendorOwnerId: VENDOR_OWNER });
}

describe("contactTargetUid — customer -> driver", () => {
  for (const status of ["driverAssigned", "pickedUp", "delivering"]) {
    it(`allows the customer to reach the assigned driver in ${status}`, () => {
      assert.equal(uid(CUSTOMER, "driver", order(status)), DRIVER);
    });
  }

  it("rejects while pending", () => {
    assert.throws(() => uid(CUSTOMER, "driver", order("pending", null)), notAuthorized);
  });

  it("rejects readyForPickup with no driver yet", () => {
    assert.throws(() => uid(CUSTOMER, "driver", order("readyForPickup", null)), notAuthorized);
  });

  for (const status of ["delivered", "cancelled"]) {
    it(`rejects the terminal status ${status}`, () => {
      assert.throws(() => uid(CUSTOMER, "driver", order(status)), notAuthorized);
    });
  }

  it("rejects another customer", () => {
    assert.throws(() => uid("customer-2", "driver", order("delivering")), notAuthorized);
  });

  it("rejects a queue driver who hasn't accepted the order", () => {
    assert.throws(() => uid("queue-driver", "driver", order("readyForPickup", null)), notAuthorized);
  });
});

describe("contactTargetUid — driver -> customer", () => {
  for (const status of ["driverAssigned", "pickedUp", "delivering"]) {
    it(`allows the assigned driver to reach the customer in ${status}`, () => {
      assert.equal(uid(DRIVER, "customer", order(status)), CUSTOMER);
    });
  }

  it("rejects a different driver", () => {
    assert.throws(() => uid("driver-2", "customer", order("delivering")), notAuthorized);
  });

  it("rejects an unassigned (queue) driver", () => {
    assert.throws(() => uid("queue-driver", "customer", order("readyForPickup", null)), notAuthorized);
  });

  for (const status of ["delivered", "cancelled"]) {
    it(`rejects the terminal status ${status}`, () => {
      assert.throws(() => uid(DRIVER, "customer", order(status)), notAuthorized);
    });
  }
});

describe("contactTargetUid — vendor -> customer", () => {
  for (const status of ["pending", "accepted", "preparing", "readyForPickup", "driverAssigned"]) {
    it(`allows the store owner to reach the customer in ${status}`, () => {
      assert.equal(uid(VENDOR_OWNER, "customer", order(status, status === "driverAssigned" ? DRIVER : null)), CUSTOMER);
    });
  }

  for (const status of ["pickedUp", "delivering", "delivered", "cancelled"]) {
    it(`rejects ${status}`, () => {
      assert.throws(() => uid(VENDOR_OWNER, "customer", order(status)), notAuthorized);
    });
  }

  it("rejects a different vendor", () => {
    assert.throws(() => uid("vendor-owner-2", "customer", order("pending", null)), notAuthorized);
  });
});

describe("contactTargetUid — vendor -> driver", () => {
  for (const status of ["driverAssigned", "pickedUp"]) {
    it(`allows the store owner to reach the assigned driver in ${status}`, () => {
      assert.equal(uid(VENDOR_OWNER, "driver", order(status)), DRIVER);
    });
  }

  it("rejects when no driver is assigned", () => {
    assert.throws(() => uid(VENDOR_OWNER, "driver", order("readyForPickup", null)), notAuthorized);
  });

  for (const status of ["preparing", "delivering", "delivered", "cancelled"]) {
    it(`rejects ${status}`, () => {
      assert.throws(() => uid(VENDOR_OWNER, "driver", order(status)), notAuthorized);
    });
  }

  it("rejects a different vendor", () => {
    assert.throws(() => uid("vendor-owner-2", "driver", order("driverAssigned")), notAuthorized);
  });
});

describe("contactTargetUid — general", () => {
  it("never resolves a vendor target (driver -> vendor is deferred)", () => {
    for (const caller of [CUSTOMER, DRIVER, VENDOR_OWNER]) {
      assert.throws(() => uid(caller, "vendor", order("driverAssigned")), notAuthorized);
    }
  });

  it("rejects an unrelated user and a missing order", () => {
    assert.throws(() => uid("stranger", "driver", order("delivering")), notAuthorized);
    assert.throws(() => uid(CUSTOMER, "driver", undefined), notAuthorized);
  });

  it("a store with no resolvable owner grants no vendor access", () => {
    assert.throws(
      () => contactTargetUid({ callerUid: VENDOR_OWNER, target: "customer", order: order("pending", null), vendorOwnerId: null }),
      notAuthorized
    );
  });
});

describe("parseContactRequest", () => {
  const invalid = assertReason("invalid-argument", "invalid-contact-request");

  it("accepts orderId + a known target, ignoring anything else", () => {
    assert.deepEqual(parseContactRequest({ orderId: "o1", target: "driver", uid: "x" }), {
      orderId: "o1",
      target: "driver",
    });
  });

  it("rejects a missing/blank orderId", () => {
    assert.throws(() => parseContactRequest({ target: "driver" }), invalid);
    assert.throws(() => parseContactRequest({ orderId: " ", target: "driver" }), invalid);
    assert.throws(() => parseContactRequest(undefined), invalid);
  });

  it("rejects an unknown target, including a raw uid", () => {
    assert.throws(() => parseContactRequest({ orderId: "o1", target: "admin" }), invalid);
    assert.throws(() => parseContactRequest({ orderId: "o1", target: "driver-1" }), invalid);
    assert.throws(() => parseContactRequest({ orderId: "o1" }), invalid);
  });
});

describe("phoneFromUser", () => {
  const unavailable = assertReason("failed-precondition", "phone-unavailable");

  it("returns the trimmed phone number", () => {
    assert.equal(phoneFromUser({ phoneNumber: " +963 11 123 4567 " }), "+963 11 123 4567");
  });

  it("reports phone-unavailable when missing, null, empty or not a string", () => {
    for (const user of [undefined, {}, { phoneNumber: null }, { phoneNumber: "  " }, { phoneNumber: 123 }]) {
      assert.throws(() => phoneFromUser(user as Record<string, unknown> | undefined), unavailable);
    }
  });
});

// Keyed by "collection/id", so each document can be set up independently.
function fakeReader(docs: Record<string, Record<string, unknown>>): DocReader {
  return {
    collection: (path: string) => ({
      doc: (id: string) => ({
        get: async () => ({ data: () => docs[`${path}/${id}`] }),
      }),
    }),
  };
}

describe("resolveOrderContact", () => {
  const docs = {
    "orders/o1": order("delivering"),
    "vendors/vendor-1": { ownerId: VENDOR_OWNER, name: "Store" },
    [`users/${DRIVER}`]: {
      phoneNumber: "+963 900 000 001",
      displayName: "Driver One",
      email: "driver@example.com",
      role: "driver",
    },
    [`users/${CUSTOMER}`]: { displayName: "No Phone", email: "c@example.com", role: "customer" },
  };

  it("returns exactly { phone } for an eligible request — no other user fields", async () => {
    const result = await resolveOrderContact(fakeReader(docs), CUSTOMER, { orderId: "o1", target: "driver" });

    assert.deepEqual(result, { phone: "+963 900 000 001" });
  });

  it("reports phone-unavailable when the target has no phone", async () => {
    await assert.rejects(
      () => resolveOrderContact(fakeReader(docs), DRIVER, { orderId: "o1", target: "customer" }),
      assertReason("failed-precondition", "phone-unavailable")
    );
  });

  it("rejects a missing order with not-found", async () => {
    await assert.rejects(
      () => resolveOrderContact(fakeReader(docs), CUSTOMER, { orderId: "nope", target: "driver" }),
      (error: unknown) => {
        assert.equal((error as { code?: string }).code, "not-found");
        return true;
      }
    );
  });

  it("rejects invalid input before reading anything", async () => {
    await assert.rejects(
      () => resolveOrderContact(fakeReader(docs), CUSTOMER, { orderId: "o1", target: "everyone" }),
      assertReason("invalid-argument", "invalid-contact-request")
    );
  });

  it("rejects an ineligible caller without revealing the phone", async () => {
    await assert.rejects(
      () => resolveOrderContact(fakeReader(docs), "stranger", { orderId: "o1", target: "driver" }),
      notAuthorized
    );
  });
});

describe("getOrderContact callable", () => {
  it("rejects an unauthenticated caller", async () => {
    const request = { data: { orderId: "o1", target: "driver" }, auth: undefined, rawRequest: {}, acceptsStreaming: false };
    await assert.rejects(
      async () => getOrderContact.run(request as unknown as Parameters<typeof getOrderContact.run>[0]),
      (error: unknown) => {
        assert.equal((error as { code?: string }).code, "unauthenticated");
        return true;
      }
    );
  });
});

// Phase 31 (C1): orderId is ONE document ID. An assigned driver may write
// any fields into orders/{id}/driverLocation/{x}; if "O/driverLocation/X"
// reached orders.doc(orderId), that crafted subdocument would be read as
// the "order" and could name any uid as the customer or driver.
describe("getOrderContact orderId validation (Phase 31)", () => {
  const invalid = assertReason("invalid-argument", "invalid-contact-request");

  it("parseContactRequest accepts ordinary IDs unchanged", () => {
    for (const id of VALID_DOC_IDS) {
      assert.deepEqual(parseContactRequest({ orderId: id, target: "driver" }), { orderId: id, target: "driver" });
    }
  });

  it("parseContactRequest rejects non-string, empty, path-like and over-long orderIds", () => {
    for (const id of INVALID_DOC_IDS) {
      assert.throws(() => parseContactRequest({ orderId: id, target: "customer" }), invalid, JSON.stringify(id));
    }
  });

  it("an injected path cannot escape orders/{orderId}: nothing is read and no phone is returned", async () => {
    const VICTIM = "victim-uid";
    const reads: string[] = [];
    const docs: Record<string, Record<string, unknown>> = {
      // What an attacking driver could have written as a driverLocation doc.
      "orders/O/driverLocation/X": { customerId: VICTIM, driverId: DRIVER, vendorId: "vendor-1", status: "delivering" },
      "orders/O": order("delivering"),
      "vendors/vendor-1": { ownerId: VENDOR_OWNER },
      [`users/${VICTIM}`]: { phoneNumber: "+963 999 999 999", role: "customer" },
    };
    const reader: DocReader = {
      collection: (path: string) => ({
        doc: (id: string) => ({
          get: async () => {
            reads.push(`${path}/${id}`);
            return { data: () => docs[`${path}/${id}`] };
          },
        }),
      }),
    };

    for (const orderId of ["O/driverLocation/X", "O/driverLocation/X/", "/O/driverLocation/X", "O\\driverLocation\\X"]) {
      for (const target of ["customer", "driver"] as const) {
        await assert.rejects(() => resolveOrderContact(reader, DRIVER, { orderId, target }), invalid, orderId);
      }
    }
    assert.deepEqual(reads, []);
  });

  it("the callable rejects an injected orderId with the same controlled error", async () => {
    const request = {
      data: { orderId: "O/driverLocation/X", target: "customer" },
      auth: { uid: DRIVER, token: {} },
      rawRequest: {},
      acceptsStreaming: false,
    };
    await assert.rejects(
      async () => getOrderContact.run(request as unknown as Parameters<typeof getOrderContact.run>[0]),
      invalid
    );
  });
});
