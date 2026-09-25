import { HttpsError, onCall } from "firebase-functions/v2/https";
import type { FunctionsErrorCode } from "firebase-functions/v2/https";

import { db } from "./admin";
import { assertIsCustomer, isValidDocId } from "./auth";

// Server-side order creation. The customer sends only what they choose —
// which vendor, which menu items and how many, and which of their own saved
// addresses — and everything else on the order (item names and prices,
// subtotal, delivery fee, total, status, driver, vendor snapshot, timestamps)
// is read or computed here from Firestore. firestore.rules denies every
// client-side order create, so this callable is the only way an order comes
// into existence (see the orders/{orderId} create rule in firestore.rules).
//
// The decision logic lives in the pure functions below (no Firestore
// instance needed), leaving `createOrder` itself as a thin transactional
// wrapper — same split as nextDeliveryStatus/assertAdminCancellable in
// orders.ts.

export const MAX_ORDER_LINES = 50;
export const MAX_LINE_QUANTITY = 99;

/**
 * Stable, machine-readable reasons carried in `HttpsError.details.reason`.
 * The mobile client maps each one to its own localized message (see
 * mobile/lib/core/errors/app_exception.dart) instead of collapsing every
 * failure into a generic "no longer available".
 */
export type CreateOrderReason =
  | "invalid-order-input"
  | "vendor-not-found"
  | "vendor-not-approved"
  | "vendor-closed"
  | "vendor-invalid-delivery-fee"
  | "vendor-invalid-minimum"
  | "vendor-invalid-owner"
  | "menu-item-not-found"
  | "menu-item-unavailable"
  | "menu-item-invalid"
  | "minimum-order-not-met"
  | "address-not-found"
  | "address-missing-location";

function orderError(
  code: FunctionsErrorCode,
  reason: CreateOrderReason,
  message: string,
  extra: Record<string, unknown> = {}
): HttpsError {
  return new HttpsError(code, message, { reason, ...extra });
}

type FirestoreData = Record<string, unknown> | undefined;

export interface RequestedLine {
  menuItemId: string;
  quantity: number;
}

export interface CreateOrderInput {
  vendorId: string;
  addressId: string;
  items: RequestedLine[];
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === "string" && value.trim().length > 0;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

function stringOrNull(value: unknown): string | null {
  return typeof value === "string" ? value : null;
}

function finiteNumberOrNull(value: unknown): number | null {
  return isFiniteNumber(value) ? value : null;
}

/**
 * Reads ONLY `vendorId`, `addressId` and `items[].{menuItemId, quantity}`
 * out of the raw callable payload. Anything else a client sends (total,
 * unitPrice, status, driverId, ...) is never looked at, so it can't
 * influence the order.
 */
export function parseCreateOrderInput(data: unknown): CreateOrderInput {
  const invalid = (message: string) =>
    orderError("invalid-argument", "invalid-order-input", message);

  if (typeof data !== "object" || data === null) throw invalid("Request body is required.");
  const raw = data as Record<string, unknown>;

  // Each ID is used as ONE document ID (vendors/{id}, users/{uid}/addresses/{id},
  // vendors/{id}/menuItems/{id}) — never a path; see isValidDocId.
  if (!isValidDocId(raw.vendorId)) throw invalid("vendorId is required and must be a valid document ID.");
  if (!isValidDocId(raw.addressId)) throw invalid("addressId is required and must be a valid document ID.");
  if (!Array.isArray(raw.items)) throw invalid("items must be an array.");
  if (raw.items.length === 0) throw invalid("An order needs at least one item.");
  if (raw.items.length > MAX_ORDER_LINES) {
    throw invalid(`An order can have at most ${MAX_ORDER_LINES} items.`);
  }

  const seen = new Set<string>();
  const items = raw.items.map((entry): RequestedLine => {
    if (typeof entry !== "object" || entry === null) throw invalid("Each item must be an object.");
    const line = entry as Record<string, unknown>;
    if (!isValidDocId(line.menuItemId)) {
      throw invalid("Each item needs a menuItemId that is a valid document ID.");
    }
    const quantity = line.quantity;
    if (
      typeof quantity !== "number" ||
      !Number.isInteger(quantity) ||
      quantity < 1 ||
      quantity > MAX_LINE_QUANTITY
    ) {
      throw invalid(`Quantity must be a whole number from 1 to ${MAX_LINE_QUANTITY}.`);
    }
    if (seen.has(line.menuItemId)) throw invalid("Each menu item may appear only once.");
    seen.add(line.menuItemId);
    return { menuItemId: line.menuItemId, quantity };
  });

  return { vendorId: raw.vendorId, addressId: raw.addressId, items };
}

export interface VendorTerms {
  deliveryFee: number;
  minimumOrderAmount: number | null;
  vendorName: string | null;
  /** The vendor owner's uid, snapshotted onto the order as vendorOwnerId. */
  vendorOwnerId: string;
  pickupAddress: string | null;
  pickupLatitude: number | null;
  pickupLongitude: number | null;
}

/**
 * Validates that the vendor can take an order right now and extracts the
 * pricing terms and snapshot fields the order needs. `deliveryFee` null or
 * missing means no fee (0), matching how the storefront has always treated
 * an unset fee.
 */
export function vendorTermsForOrder(vendor: FirestoreData): VendorTerms {
  if (!vendor) throw orderError("not-found", "vendor-not-found", "Vendor does not exist.");
  if (vendor.approvalStatus !== "approved") {
    throw orderError("failed-precondition", "vendor-not-approved", "Vendor is not approved.");
  }
  if (vendor.isOpen !== true) {
    throw orderError("failed-precondition", "vendor-closed", "Vendor is currently closed.");
  }
  // The owner's uid is snapshotted onto the order (vendorOwnerId) so
  // storage.rules can recognise the vendor owner from the order alone. It
  // always comes from the vendor document, never from the request.
  if (!isValidDocId(vendor.ownerId)) {
    throw orderError("failed-precondition", "vendor-invalid-owner", "Vendor has no valid owner.");
  }

  let deliveryFee = 0;
  if (vendor.deliveryFee !== undefined && vendor.deliveryFee !== null) {
    if (!isFiniteNumber(vendor.deliveryFee) || vendor.deliveryFee < 0) {
      throw orderError(
        "failed-precondition",
        "vendor-invalid-delivery-fee",
        "Vendor delivery fee is invalid."
      );
    }
    deliveryFee = vendor.deliveryFee;
  }

  let minimumOrderAmount: number | null = null;
  if (vendor.minimumOrderAmount !== undefined && vendor.minimumOrderAmount !== null) {
    if (!isFiniteNumber(vendor.minimumOrderAmount) || vendor.minimumOrderAmount < 0) {
      throw orderError(
        "failed-precondition",
        "vendor-invalid-minimum",
        "Vendor minimum order amount is invalid."
      );
    }
    minimumOrderAmount = vendor.minimumOrderAmount;
  }

  return {
    deliveryFee,
    minimumOrderAmount,
    vendorOwnerId: vendor.ownerId,
    vendorName: stringOrNull(vendor.name),
    pickupAddress: stringOrNull(vendor.pickupAddress),
    pickupLatitude: finiteNumberOrNull(vendor.pickupLatitude),
    pickupLongitude: finiteNumberOrNull(vendor.pickupLongitude),
  };
}

export interface DeliveryDetails {
  deliveryAddress: string;
  deliveryLatitude: number;
  deliveryLongitude: number;
  governorateId: string | null;
  cityId: string | null;
  neighborhoodId: string | null;
  deliveryInstructions: string | null;
  driverNote: string | null;
}

/**
 * Validates the customer's saved address (already read from
 * users/{uid}/addresses/{addressId}, so ownership is proven by the path)
 * and copies the delivery fields off it. New orders require a real
 * coordinate pair — no more text-only deliveries.
 */
export function deliveryDetailsFromAddress(address: FirestoreData): DeliveryDetails {
  if (!address) {
    throw orderError("not-found", "address-not-found", "Delivery address does not exist.");
  }
  // Pre-Phase-4 saved addresses stored the text under `address` — same
  // fallback as SavedAddress.fromMap on the client.
  const addressText = address.addressText ?? address.address;
  if (!isNonEmptyString(addressText)) {
    throw orderError(
      "failed-precondition",
      "address-missing-location",
      "Delivery address has no address text."
    );
  }
  const latitude = address.latitude;
  const longitude = address.longitude;
  if (
    !isFiniteNumber(latitude) ||
    !isFiniteNumber(longitude) ||
    latitude < -90 ||
    latitude > 90 ||
    longitude < -180 ||
    longitude > 180
  ) {
    throw orderError(
      "failed-precondition",
      "address-missing-location",
      "Delivery address needs a valid map location."
    );
  }

  return {
    deliveryAddress: addressText,
    deliveryLatitude: latitude,
    deliveryLongitude: longitude,
    governorateId: stringOrNull(address.governorateId),
    cityId: stringOrNull(address.cityId),
    neighborhoodId: stringOrNull(address.neighborhoodId),
    deliveryInstructions: stringOrNull(address.deliveryInstructions),
    driverNote: stringOrNull(address.driverNote),
  };
}

export interface PricedItem {
  menuItemId: string;
  name: string;
  quantity: number;
  unitPrice: number;
}

/**
 * Prices each requested line from its menu item document, read at
 * vendors/{vendorId}/menuItems/{menuItemId} — the path is the ownership
 * proof, so the doc's own `vendorId` field is never consulted.
 * [menuItems] is index-aligned with [lines]. A missing `available` counts
 * as available, matching MenuItem.fromMap on the client.
 */
export function priceOrderLines(
  lines: RequestedLine[],
  menuItems: FirestoreData[]
): { items: PricedItem[]; subtotal: number } {
  const items = lines.map((line, index): PricedItem => {
    const menuItem = menuItems[index];
    const details = { menuItemId: line.menuItemId };
    if (!menuItem) {
      throw orderError("not-found", "menu-item-not-found", "Menu item does not exist.", details);
    }
    if (menuItem.available === false) {
      throw orderError(
        "failed-precondition",
        "menu-item-unavailable",
        "Menu item is unavailable.",
        details
      );
    }
    if (!isFiniteNumber(menuItem.price) || menuItem.price < 0 || !isNonEmptyString(menuItem.name)) {
      throw orderError("failed-precondition", "menu-item-invalid", "Menu item is invalid.", details);
    }
    return {
      menuItemId: line.menuItemId,
      name: menuItem.name,
      quantity: line.quantity,
      unitPrice: menuItem.price,
    };
  });

  const subtotal = items.reduce((sum, item) => sum + item.unitPrice * item.quantity, 0);
  return { items, subtotal };
}

export interface OrderPlan {
  order: Record<string, unknown>;
  subtotal: number;
  deliveryFee: number;
  total: number;
}

/**
 * The whole server-side decision for one order: validates the vendor,
 * address and menu items, applies the minimum order (against the item
 * subtotal, excluding the delivery fee), and builds the exact document to
 * write. Pure — every Firestore read is passed in.
 */
export function planOrder(params: {
  customerId: string;
  input: CreateOrderInput;
  vendor: FirestoreData;
  address: FirestoreData;
  menuItems: FirestoreData[];
  now: number;
}): OrderPlan {
  const { customerId, input, vendor, address, menuItems, now } = params;

  const terms = vendorTermsForOrder(vendor);
  const delivery = deliveryDetailsFromAddress(address);
  const { items, subtotal } = priceOrderLines(input.items, menuItems);

  if (terms.minimumOrderAmount !== null && subtotal < terms.minimumOrderAmount) {
    throw orderError(
      "failed-precondition",
      "minimum-order-not-met",
      "Order subtotal is below the vendor's minimum.",
      { minimumOrderAmount: terms.minimumOrderAmount, subtotal }
    );
  }

  const deliveryFee = terms.deliveryFee;
  const total = subtotal + deliveryFee;

  const order: Record<string, unknown> = {
    customerId,
    vendorId: input.vendorId,
    driverId: null,
    items,
    status: "pending",
    subtotal,
    deliveryFee,
    total,
    deliveryAddress: delivery.deliveryAddress,
    // Integer milliseconds, not a Firestore Timestamp — DeliveryOrder.fromMap
    // reads `createdAt as int`, and every order query/index sorts on it.
    createdAt: now,
    proofImageUrl: null,
    deliveryLatitude: delivery.deliveryLatitude,
    deliveryLongitude: delivery.deliveryLongitude,
    governorateId: delivery.governorateId,
    cityId: delivery.cityId,
    neighborhoodId: delivery.neighborhoodId,
    deliveryInstructions: delivery.deliveryInstructions,
    driverNote: delivery.driverNote,
    vendorOwnerId: terms.vendorOwnerId,
    vendorName: terms.vendorName,
    pickupAddress: terms.pickupAddress,
    pickupLatitude: terms.pickupLatitude,
    pickupLongitude: terms.pickupLongitude,
  };

  return { order, subtotal, deliveryFee, total };
}

/**
 * Creates an order on a customer's behalf. Reads the vendor, the
 * customer's saved address and every requested menu item inside one
 * transaction, so the order reflects a single consistent snapshot of the
 * vendor's approval/open state, prices, names, fee and minimum — then
 * writes the order in that same transaction (all or nothing).
 */
export const createOrder = onCall(async (request) => {
  const customerUid = request.auth?.uid;
  if (!customerUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as a customer.");
  }

  const input = parseCreateOrderInput(request.data);

  await assertIsCustomer(db, customerUid);

  const vendorRef = db.collection("vendors").doc(input.vendorId);
  const addressRef = db
    .collection("users")
    .doc(customerUid)
    .collection("addresses")
    .doc(input.addressId);
  const menuItemRefs = input.items.map((line) =>
    vendorRef.collection("menuItems").doc(line.menuItemId)
  );
  const orderRef = db.collection("orders").doc();

  const plan = await db.runTransaction(async (transaction) => {
    const [vendorSnap, addressSnap, ...menuItemSnaps] = await transaction.getAll(
      vendorRef,
      addressRef,
      ...menuItemRefs
    );
    const result = planOrder({
      customerId: customerUid,
      input,
      vendor: vendorSnap.data(),
      address: addressSnap.data(),
      menuItems: menuItemSnaps.map((snap) => snap.data()),
      now: Date.now(),
    });
    transaction.set(orderRef, result.order);
    return result;
  });

  return {
    orderId: orderRef.id,
    subtotal: plan.subtotal,
    deliveryFee: plan.deliveryFee,
    total: plan.total,
  };
});
