import assert from "node:assert/strict";

import {
  createOrder,
  deliveryDetailsFromAddress,
  MAX_LINE_QUANTITY,
  MAX_ORDER_LINES,
  parseCreateOrderInput,
  planOrder,
  priceOrderLines,
  vendorTermsForOrder,
} from "./createOrder";

// Lettered comments map each case to the Step 3 test plan (A-AN).
// Non-customer rejection (B) lives in auth.spec.ts's assertIsCustomer suite,
// the same way assertIsDriver/assertIsAdmin are tested for the other
// callables.

function assertOrderError(code: string, reason: string) {
  return (error: unknown): true => {
    assert.ok(error instanceof Error);
    assert.equal((error as { code?: string }).code, code);
    assert.equal((error as { details?: { reason?: string } }).details?.reason, reason);
    return true;
  };
}

import { INVALID_DOC_IDS, VALID_DOC_IDS } from "./auth.spec";

const invalidInput = assertOrderError("invalid-argument", "invalid-order-input");

function validVendor(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    ownerId: "owner-1",
    name: "Abu Kamal Falafel",
    approvalStatus: "approved",
    isOpen: true,
    deliveryFee: 1500,
    minimumOrderAmount: 5000,
    pickupAddress: "Hamra St, Damascus",
    pickupLatitude: 33.5138,
    pickupLongitude: 36.2765,
    ...overrides,
  };
}

function validAddress(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    userId: "customer-1",
    label: "Home",
    addressText: "Mezzeh, Building 4",
    latitude: 33.5,
    longitude: 36.25,
    governorateId: "damascus-gov",
    cityId: "damascus",
    neighborhoodId: "mezzeh",
    deliveryInstructions: "Ring twice",
    driverNote: "Leave at door",
    isDefault: true,
    ...overrides,
  };
}

function menuItem(name: string, price: number, overrides: Record<string, unknown> = {}) {
  return { vendorId: "vendor-1", name, price, available: true, orderCount: 3, ...overrides };
}

function validInput(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    vendorId: "vendor-1",
    addressId: "address-1",
    items: [
      { menuItemId: "falafel", quantity: 2 },
      { menuItemId: "hummus", quantity: 1 },
    ],
    ...overrides,
  };
}

function plan(overrides: {
  input?: Record<string, unknown>;
  vendor?: Record<string, unknown> | undefined;
  address?: Record<string, unknown> | undefined;
  menuItems?: Array<Record<string, unknown> | undefined>;
} = {}) {
  return planOrder({
    customerId: "customer-1",
    input: parseCreateOrderInput(overrides.input ?? validInput()),
    vendor: "vendor" in overrides ? overrides.vendor : validVendor(),
    address: "address" in overrides ? overrides.address : validAddress(),
    menuItems: overrides.menuItems ?? [menuItem("Falafel", 2000), menuItem("Hummus", 3000)],
    now: 1700000000000,
  });
}

describe("createOrder callable", () => {
  it("(A) rejects an unauthenticated caller before reading anything", async () => {
    const request = { data: validInput(), auth: undefined, rawRequest: {}, acceptsStreaming: false };
    await assert.rejects(
      async () => createOrder.run(request as unknown as Parameters<typeof createOrder.run>[0]),
      (error: unknown) => {
        assert.equal((error as { code?: string }).code, "unauthenticated");
        return true;
      }
    );
  });
});

describe("parseCreateOrderInput", () => {
  it("keeps only vendorId, addressId and items[].{menuItemId, quantity}", () => {
    const input = parseCreateOrderInput({
      ...validInput(),
      // (N)(O)(P)(Q) tampered fields a client might add — never read.
      total: 1,
      subtotal: 1,
      deliveryFee: 0,
      status: "delivered",
      driverId: "customer-1",
      customerId: "someone-else",
      items: [{ menuItemId: "falafel", quantity: 2, unitPrice: 1, name: "Free food" }],
    });
    assert.deepEqual(input, {
      vendorId: "vendor-1",
      addressId: "address-1",
      items: [{ menuItemId: "falafel", quantity: 2 }],
    });
  });

  it("rejects a missing body, vendorId or addressId", () => {
    assert.throws(() => parseCreateOrderInput(undefined), invalidInput);
    assert.throws(() => parseCreateOrderInput(validInput({ vendorId: "" })), invalidInput);
    assert.throws(() => parseCreateOrderInput(validInput({ vendorId: 7 })), invalidInput);
    assert.throws(() => parseCreateOrderInput(validInput({ addressId: " " })), invalidInput);
  });

  it("(X) rejects an empty or non-array item list", () => {
    assert.throws(() => parseCreateOrderInput(validInput({ items: [] })), invalidInput);
    assert.throws(() => parseCreateOrderInput(validInput({ items: "falafel" })), invalidInput);
  });

  it("(W) rejects more than the maximum number of lines", () => {
    const items = Array.from({ length: MAX_ORDER_LINES + 1 }, (_, i) => ({
      menuItemId: `item-${i}`,
      quantity: 1,
    }));
    assert.throws(() => parseCreateOrderInput(validInput({ items })), invalidInput);
  });

  it("accepts exactly the maximum number of lines", () => {
    const items = Array.from({ length: MAX_ORDER_LINES }, (_, i) => ({
      menuItemId: `item-${i}`,
      quantity: 1,
    }));
    assert.equal(parseCreateOrderInput(validInput({ items })).items.length, MAX_ORDER_LINES);
  });

  const badQuantities: Array<[string, unknown]> = [
    ["(R) zero", 0],
    ["(S) negative", -1],
    ["(T) fractional", 1.5],
    ["(U) string", "2"],
    ["(V) above the maximum", MAX_LINE_QUANTITY + 1],
    ["NaN", Number.NaN],
    ["missing", undefined],
  ];
  for (const [label, quantity] of badQuantities) {
    it(`rejects a ${label} quantity`, () => {
      assert.throws(
        () => parseCreateOrderInput(validInput({ items: [{ menuItemId: "falafel", quantity }] })),
        invalidInput
      );
    });
  }

  it("accepts quantities 1 and the maximum", () => {
    const input = parseCreateOrderInput(
      validInput({
        items: [
          { menuItemId: "falafel", quantity: 1 },
          { menuItemId: "hummus", quantity: MAX_LINE_QUANTITY },
        ],
      })
    );
    assert.deepEqual(
      input.items.map((line) => line.quantity),
      [1, MAX_LINE_QUANTITY]
    );
  });

  it("rejects a line without a menuItemId", () => {
    assert.throws(
      () => parseCreateOrderInput(validInput({ items: [{ quantity: 1 }] })),
      invalidInput
    );
  });

  it("(Y) rejects duplicate menuItemIds", () => {
    assert.throws(
      () =>
        parseCreateOrderInput(
          validInput({
            items: [
              { menuItemId: "falafel", quantity: 1 },
              { menuItemId: "falafel", quantity: 2 },
            ],
          })
        ),
      invalidInput
    );
  });
});

describe("vendorTermsForOrder", () => {
  it("(D) rejects a missing vendor", () => {
    assert.throws(() => vendorTermsForOrder(undefined), assertOrderError("not-found", "vendor-not-found"));
  });

  for (const approvalStatus of ["pending", "rejected", undefined]) {
    it(`(E)(F) rejects a vendor with approvalStatus '${approvalStatus}'`, () => {
      assert.throws(
        () => vendorTermsForOrder(validVendor({ approvalStatus })),
        assertOrderError("failed-precondition", "vendor-not-approved")
      );
    });
  }

  for (const isOpen of [false, undefined, "true"]) {
    it(`(G) rejects a vendor with isOpen ${JSON.stringify(isOpen)}`, () => {
      assert.throws(
        () => vendorTermsForOrder(validVendor({ isOpen })),
        assertOrderError("failed-precondition", "vendor-closed")
      );
    });
  }

  for (const deliveryFee of [-1, "1500", Number.NaN, Number.POSITIVE_INFINITY]) {
    it(`(H) rejects an invalid delivery fee ${String(deliveryFee)}`, () => {
      assert.throws(
        () => vendorTermsForOrder(validVendor({ deliveryFee })),
        assertOrderError("failed-precondition", "vendor-invalid-delivery-fee")
      );
    });
  }

  for (const minimumOrderAmount of [-5, "5000", Number.NaN]) {
    it(`(I) rejects an invalid minimum ${String(minimumOrderAmount)}`, () => {
      assert.throws(
        () => vendorTermsForOrder(validVendor({ minimumOrderAmount })),
        assertOrderError("failed-precondition", "vendor-invalid-minimum")
      );
    });
  }

  it("(AC) treats a null or missing delivery fee as 0, and keeps 0 as 0", () => {
    assert.equal(vendorTermsForOrder(validVendor({ deliveryFee: null })).deliveryFee, 0);
    const withoutFee = validVendor();
    delete withoutFee.deliveryFee;
    assert.equal(vendorTermsForOrder(withoutFee).deliveryFee, 0);
    assert.equal(vendorTermsForOrder(validVendor({ deliveryFee: 0 })).deliveryFee, 0);
  });

  it("treats a null or missing minimum as no minimum", () => {
    assert.equal(vendorTermsForOrder(validVendor({ minimumOrderAmount: null })).minimumOrderAmount, null);
    const withoutMinimum = validVendor();
    delete withoutMinimum.minimumOrderAmount;
    assert.equal(vendorTermsForOrder(withoutMinimum).minimumOrderAmount, null);
  });

  it("(AM) handles a vendor with no pickup fields (all null, nothing invented)", () => {
    const legacy = validVendor();
    delete legacy.pickupAddress;
    delete legacy.pickupLatitude;
    delete legacy.pickupLongitude;
    const terms = vendorTermsForOrder(legacy);
    assert.equal(terms.pickupAddress, null);
    assert.equal(terms.pickupLatitude, null);
    assert.equal(terms.pickupLongitude, null);
    assert.equal(terms.vendorName, "Abu Kamal Falafel");
  });
});

describe("deliveryDetailsFromAddress", () => {
  it("(AH) copies the delivery fields off the saved address", () => {
    assert.deepEqual(deliveryDetailsFromAddress(validAddress()), {
      deliveryAddress: "Mezzeh, Building 4",
      deliveryLatitude: 33.5,
      deliveryLongitude: 36.25,
      governorateId: "damascus-gov",
      cityId: "damascus",
      neighborhoodId: "mezzeh",
      deliveryInstructions: "Ring twice",
      driverNote: "Leave at door",
    });
  });

  it("falls back to the pre-Phase-4 `address` text field", () => {
    const legacy = validAddress({ address: "Old text" });
    delete legacy.addressText;
    assert.equal(deliveryDetailsFromAddress(legacy).deliveryAddress, "Old text");
  });

  it("stores missing optional classification/notes as null", () => {
    const minimal = { addressText: "Somewhere", latitude: 33.5, longitude: 36.25 };
    const details = deliveryDetailsFromAddress(minimal);
    assert.equal(details.governorateId, null);
    assert.equal(details.neighborhoodId, null);
    assert.equal(details.deliveryInstructions, null);
    assert.equal(details.driverNote, null);
  });

  it("(AI) rejects an address that doesn't exist under the caller's own path", () => {
    // A foreign addressId is read at users/{auth.uid}/addresses/{addressId},
    // so another customer's address id simply resolves to no document.
    assert.throws(
      () => deliveryDetailsFromAddress(undefined),
      assertOrderError("not-found", "address-not-found")
    );
  });

  it("rejects an address without text", () => {
    assert.throws(
      () => deliveryDetailsFromAddress(validAddress({ addressText: "  " })),
      assertOrderError("failed-precondition", "address-missing-location")
    );
  });

  const missingLocation: Array<[string, Record<string, unknown>]> = [
    ["(AJ) no latitude", { latitude: null }],
    ["(AJ) no longitude", { longitude: undefined }],
    ["(AJ) string coordinates", { latitude: "33.5" }],
    ["(AK) latitude above 90", { latitude: 90.0001 }],
    ["(AK) latitude below -90", { latitude: -91 }],
    ["(AL) longitude above 180", { longitude: 180.5 }],
    ["(AL) longitude below -180", { longitude: -181 }],
  ];
  for (const [label, overrides] of missingLocation) {
    it(`rejects ${label}`, () => {
      assert.throws(
        () => deliveryDetailsFromAddress(validAddress(overrides)),
        assertOrderError("failed-precondition", "address-missing-location")
      );
    });
  }

  it("accepts the coordinate boundaries", () => {
    const details = deliveryDetailsFromAddress(validAddress({ latitude: -90, longitude: 180 }));
    assert.equal(details.deliveryLatitude, -90);
    assert.equal(details.deliveryLongitude, 180);
  });
});

describe("priceOrderLines", () => {
  const lines = [{ menuItemId: "falafel", quantity: 2 }];

  it("(J)(M) rejects a menu item that doesn't exist under this vendor's path", () => {
    // (M) Another vendor's menuItemId is looked up under the ordered vendor's
    // menuItems path, where it doesn't exist.
    assert.throws(
      () => priceOrderLines(lines, [undefined]),
      assertOrderError("not-found", "menu-item-not-found")
    );
  });

  it("(K) rejects an unavailable menu item", () => {
    assert.throws(
      () => priceOrderLines(lines, [menuItem("Falafel", 2000, { available: false })]),
      assertOrderError("failed-precondition", "menu-item-unavailable")
    );
  });

  const malformed: Array<[string, Record<string, unknown>]> = [
    ["negative price", { price: -1 }],
    ["string price", { price: "2000" }],
    ["NaN price", { price: Number.NaN }],
    ["missing name", { name: undefined }],
    ["empty name", { name: "" }],
  ];
  for (const [label, overrides] of malformed) {
    it(`(L) rejects a malformed menu item: ${label}`, () => {
      assert.throws(
        () => priceOrderLines(lines, [menuItem("Falafel", 2000, overrides)]),
        assertOrderError("failed-precondition", "menu-item-invalid")
      );
    });
  }

  it("(AN) treats a menu item without an `available` field as available", () => {
    const item = menuItem("Falafel", 2000);
    delete (item as Record<string, unknown>).available;
    assert.equal(priceOrderLines(lines, [item]).subtotal, 4000);
  });

  it("ignores the menu item's own vendorId field (the path is the ownership proof)", () => {
    const priced = priceOrderLines(lines, [menuItem("Falafel", 2000, { vendorId: "other-vendor" })]);
    assert.equal(priced.subtotal, 4000);
  });

  it("allows a free (price 0) item", () => {
    assert.equal(priceOrderLines(lines, [menuItem("Free sample", 0)]).subtotal, 0);
  });
});

describe("planOrder", () => {
  it("(C)(AB)(AC)(AD) prices a valid order from server data", () => {
    const result = plan();
    // 2 x 2000 + 1 x 3000
    assert.equal(result.subtotal, 7000);
    assert.equal(result.deliveryFee, 1500);
    assert.equal(result.total, 8500);
  });

  it("(C) writes exactly the expected order document", () => {
    assert.deepEqual(plan().order, {
      customerId: "customer-1",
      vendorId: "vendor-1",
      driverId: null,
      items: [
        { menuItemId: "falafel", name: "Falafel", quantity: 2, unitPrice: 2000 },
        { menuItemId: "hummus", name: "Hummus", quantity: 1, unitPrice: 3000 },
      ],
      status: "pending",
      subtotal: 7000,
      deliveryFee: 1500,
      total: 8500,
      deliveryAddress: "Mezzeh, Building 4",
      createdAt: 1700000000000,
      proofImageUrl: null,
      deliveryLatitude: 33.5,
      deliveryLongitude: 36.25,
      governorateId: "damascus-gov",
      cityId: "damascus",
      neighborhoodId: "mezzeh",
      deliveryInstructions: "Ring twice",
      driverNote: "Leave at door",
      vendorOwnerId: "owner-1",
      vendorName: "Abu Kamal Falafel",
      pickupAddress: "Hamra St, Damascus",
      pickupLatitude: 33.5138,
      pickupLongitude: 36.2765,
    });
  });

  it("(N)(O)(P)(Q)(AE)(AF) ignores tampered prices, totals, fee, names, status and driver", () => {
    const result = plan({
      input: {
        ...validInput(),
        total: 1,
        subtotal: 1,
        deliveryFee: 0,
        status: "delivered",
        driverId: "customer-1",
        vendorName: "Fake",
        pickupAddress: "Fake",
        items: [
          { menuItemId: "falafel", quantity: 2, unitPrice: 1, name: "Free food" },
          { menuItemId: "hummus", quantity: 1, unitPrice: 1, name: "Free food" },
        ],
      },
    });
    assert.equal(result.total, 8500);
    assert.equal(result.order.subtotal, 7000);
    assert.equal(result.order.deliveryFee, 1500);
    assert.equal(result.order.status, "pending");
    assert.equal(result.order.driverId, null);
    assert.equal(result.order.customerId, "customer-1");
    assert.equal(result.order.vendorName, "Abu Kamal Falafel");
    assert.deepEqual(
      (result.order.items as Array<{ name: string; unitPrice: number }>).map((item) => [
        item.name,
        item.unitPrice,
      ]),
      [
        ["Falafel", 2000],
        ["Hummus", 3000],
      ]
    );
  });

  it("(AE)(AF) always starts pending with no driver, no proof, and integer createdAt", () => {
    const { order } = plan();
    assert.equal(order.status, "pending");
    assert.equal(order.driverId, null);
    assert.equal(order.proofImageUrl, null);
    assert.ok(Number.isInteger(order.createdAt));
  });

  it("(AG) snapshots the vendor's name and pickup location", () => {
    const { order } = plan();
    assert.equal(order.vendorName, "Abu Kamal Falafel");
    assert.equal(order.pickupAddress, "Hamra St, Damascus");
    assert.equal(order.pickupLatitude, 33.5138);
    assert.equal(order.pickupLongitude, 36.2765);
  });

  it("(Z) rejects a subtotal below the vendor minimum", () => {
    assert.throws(
      () => plan({ vendor: validVendor({ minimumOrderAmount: 7001 }) }),
      assertOrderError("failed-precondition", "minimum-order-not-met")
    );
  });

  it("(Z) checks the minimum against the subtotal, not the total incl. delivery fee", () => {
    // subtotal 7000 + fee 1500 = 8500 >= 8000, but the subtotal alone is below.
    assert.throws(
      () => plan({ vendor: validVendor({ minimumOrderAmount: 8000 }) }),
      assertOrderError("failed-precondition", "minimum-order-not-met")
    );
  });

  it("(AA) accepts a subtotal exactly at the minimum", () => {
    assert.equal(plan({ vendor: validVendor({ minimumOrderAmount: 7000 }) }).subtotal, 7000);
  });

  it("(AC)(AD) a vendor without a delivery fee is total = subtotal", () => {
    const result = plan({ vendor: validVendor({ deliveryFee: null }) });
    assert.equal(result.deliveryFee, 0);
    assert.equal(result.total, result.subtotal);
  });

  it("(AM) writes null pickup snapshot fields for a vendor that hasn't set them", () => {
    const vendor = validVendor();
    delete vendor.pickupAddress;
    delete vendor.pickupLatitude;
    delete vendor.pickupLongitude;
    const { order } = plan({ vendor });
    assert.equal(order.pickupAddress, null);
    assert.equal(order.pickupLatitude, null);
    assert.equal(order.pickupLongitude, null);
  });

  it("rejects the whole order if any single line is invalid", () => {
    assert.throws(
      () => plan({ menuItems: [menuItem("Falafel", 2000), undefined] }),
      assertOrderError("not-found", "menu-item-not-found")
    );
  });
});

// Phase 31 (M4): vendorId, addressId and every menuItemId are single
// document IDs (vendors/{id}, users/{uid}/addresses/{id},
// vendors/{id}/menuItems/{id}) — never paths into other documents.
describe("createOrder document-ID validation (Phase 31)", () => {
  it("accepts ordinary IDs for vendorId, addressId and menuItemId", () => {
    for (const id of VALID_DOC_IDS) {
      const input = parseCreateOrderInput(
        validInput({ vendorId: id, addressId: id, items: [{ menuItemId: id, quantity: 1 }] })
      );
      assert.deepEqual(input, { vendorId: id, addressId: id, items: [{ menuItemId: id, quantity: 1 }] });
    }
  });

  for (const field of ["vendorId", "addressId"] as const) {
    it(`rejects an invalid ${field} with invalid-order-input`, () => {
      for (const id of INVALID_DOC_IDS) {
        assert.throws(() => parseCreateOrderInput(validInput({ [field]: id })), invalidInput, JSON.stringify(id));
      }
    });
  }

  it("rejects an invalid menuItemId in any line with invalid-order-input", () => {
    for (const id of INVALID_DOC_IDS) {
      const items = [
        { menuItemId: "falafel", quantity: 1 },
        { menuItemId: id, quantity: 1 },
      ];
      assert.throws(() => parseCreateOrderInput(validInput({ items })), invalidInput, JSON.stringify(id));
    }
  });

  it("rejects path-injected IDs such as a menu item path passed as vendorId", () => {
    for (const input of [
      validInput({ vendorId: "vendor-1/menuItems/falafel" }),
      validInput({ addressId: "home/../other" }),
      validInput({ items: [{ menuItemId: "falafel/menuItems/x", quantity: 1 }] }),
    ]) {
      assert.throws(() => parseCreateOrderInput(input), invalidInput);
    }
  });

  it("the callable rejects an injected vendorId before any role or Firestore read", async () => {
    const request = {
      data: validInput({ vendorId: "vendor-1/menuItems/falafel" }),
      auth: { uid: "customer-1", token: {} },
      rawRequest: {},
      acceptsStreaming: false,
    };
    await assert.rejects(
      async () => createOrder.run(request as unknown as Parameters<typeof createOrder.run>[0]),
      invalidInput
    );
  });
});

// Phase 32 (proof access): every order carries vendorOwnerId, taken from
// the vendor document inside createOrder's transaction — storage.rules
// recognise the vendor owner from it without a second lookup.
describe("vendorOwnerId snapshot (Phase 32)", () => {
  it("is derived from the vendor document's ownerId", () => {
    assert.equal(vendorTermsForOrder(validVendor()).vendorOwnerId, "owner-1");
    assert.equal(plan().order.vendorOwnerId, "owner-1");
    assert.equal(plan({ vendor: validVendor({ ownerId: "someone-else" }) }).order.vendorOwnerId, "someone-else");
  });

  it("can't be supplied or fabricated by the client", () => {
    const tampered = { ...validInput(), vendorOwnerId: "attacker", ownerId: "attacker" };
    assert.equal("vendorOwnerId" in parseCreateOrderInput(tampered), false);
    assert.equal(plan({ input: tampered }).order.vendorOwnerId, "owner-1");
  });

  it("rejects a vendor without a valid ownerId (no order is planned)", () => {
    for (const ownerId of [undefined, null, "", "  ", 42, "a/b", "x".repeat(200)]) {
      assert.throws(
        () => plan({ vendor: validVendor({ ownerId }) }),
        assertOrderError("failed-precondition", "vendor-invalid-owner"),
        JSON.stringify(ownerId)
      );
    }
  });

  it("is present on every planned order next to the existing vendor snapshot fields", () => {
    const order = plan().order;
    for (const key of ["vendorId", "vendorOwnerId", "vendorName", "pickupAddress", "pickupLatitude", "pickupLongitude"]) {
      assert.ok(key in order, key);
    }
  });
});
