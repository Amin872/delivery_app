import { HttpsError, onCall } from "firebase-functions/v2/https";

import { db } from "./admin";
import { isValidDocId, type DocReader } from "./auth";

// Contact resolver: lets an order's participants phone each other without
// ever making a phone number client-readable. users/{uid} stays readable
// only by its owner and admins (firestore.rules), and no phone is ever
// written onto an order (whose unclaimed readyForPickup state is visible to
// every approved driver). Instead the caller asks for "the driver of this
// order" / "the customer of this order"; the server checks participation
// and status, derives the target account from the order itself (never from
// client input), and returns just that account's phone number.
//
// Decision logic lives in the pure functions below; `getOrderContact` is a
// thin read-only wrapper — same split as createOrder.ts / orders.ts.

export type ContactTarget = "customer" | "driver" | "vendor";

export type ContactReason = "invalid-contact-request" | "contact-not-authorized" | "phone-unavailable";

function contactError(
  code: "invalid-argument" | "permission-denied" | "failed-precondition",
  reason: ContactReason,
  message: string
): HttpsError {
  return new HttpsError(code, message, { reason });
}

// Customer <-> assigned driver, once a driver has the order and until it's done.
export const CUSTOMER_DRIVER_STATUSES = new Set(["driverAssigned", "pickedUp", "delivering"]);
// Vendor -> customer, while the vendor is still handling the order.
export const VENDOR_CUSTOMER_STATUSES = new Set([
  "pending",
  "accepted",
  "preparing",
  "readyForPickup",
  "driverAssigned",
]);
// Vendor <-> assigned driver, around the pickup.
export const VENDOR_DRIVER_STATUSES = new Set(["driverAssigned", "pickedUp"]);

export interface ContactRequest {
  orderId: string;
  target: ContactTarget;
}

/** Reads only orderId and target from the raw callable payload. */
export function parseContactRequest(data: unknown): ContactRequest {
  const invalid = (message: string) => contactError("invalid-argument", "invalid-contact-request", message);
  if (typeof data !== "object" || data === null) throw invalid("Request body is required.");
  const raw = data as Record<string, unknown>;
  // orderId must be ONE document ID: "O/driverLocation/X" would otherwise
  // make orders.doc(orderId) read a driver-writable subdocument whose
  // fields the caller controls (see isValidDocId).
  if (!isValidDocId(raw.orderId)) {
    throw invalid("orderId is required and must be a valid document ID.");
  }
  if (raw.target !== "customer" && raw.target !== "driver" && raw.target !== "vendor") {
    throw invalid("target must be customer, driver or vendor.");
  }
  return { orderId: raw.orderId, target: raw.target };
}

type FirestoreData = Record<string, unknown> | undefined;

function nonEmptyString(value: unknown): string | null {
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

/**
 * The uid whose phone [callerUid] may have for [target] on [order], or
 * throws permission-denied (reason contact-not-authorized). [vendorOwnerId]
 * is vendors/{order.vendorId}.ownerId — the same ownership field
 * firestore.rules checks. Allowed:
 *   customer -> driver:  own order, driver assigned, CUSTOMER_DRIVER_STATUSES
 *   driver   -> customer: the assigned driver, CUSTOMER_DRIVER_STATUSES
 *   vendor   -> customer: the order's store owner, VENDOR_CUSTOMER_STATUSES
 *   vendor   -> driver:  the order's store owner, driver assigned, VENDOR_DRIVER_STATUSES
 * Anything else — including every "vendor" target (driver -> vendor is
 * deliberately not offered), unrelated users, other participants' orders,
 * queue drivers who haven't accepted, and terminal orders — is refused
 * with the same reason, so a refusal reveals nothing about the order.
 */
export function contactTargetUid(params: {
  callerUid: string;
  target: ContactTarget;
  order: FirestoreData;
  vendorOwnerId: string | null;
}): string {
  const { callerUid, target, order, vendorOwnerId } = params;
  const refuse = () =>
    contactError("permission-denied", "contact-not-authorized", "You can't contact this person for this order.");
  if (!order) throw refuse();

  const status = typeof order.status === "string" ? order.status : "";
  const customerId = nonEmptyString(order.customerId);
  const driverId = nonEmptyString(order.driverId);
  const isCustomer = customerId !== null && callerUid === customerId;
  const isAssignedDriver = driverId !== null && callerUid === driverId;
  const isVendorOwner = vendorOwnerId !== null && callerUid === vendorOwnerId;

  if (target === "driver" && driverId !== null) {
    if (isCustomer && CUSTOMER_DRIVER_STATUSES.has(status)) return driverId;
    if (isVendorOwner && VENDOR_DRIVER_STATUSES.has(status)) return driverId;
  }
  if (target === "customer" && customerId !== null) {
    if (isAssignedDriver && CUSTOMER_DRIVER_STATUSES.has(status)) return customerId;
    if (isVendorOwner && VENDOR_CUSTOMER_STATUSES.has(status)) return customerId;
  }
  throw refuse();
}

/**
 * The target account's phone number, or throws failed-precondition (reason
 * phone-unavailable) when there is none. Returns nothing else from the
 * user document.
 */
export function phoneFromUser(user: FirestoreData): string {
  const phone = typeof user?.phoneNumber === "string" ? user.phoneNumber.trim() : "";
  if (phone.length === 0) {
    throw contactError("failed-precondition", "phone-unavailable", "No phone number is available for this person.");
  }
  return phone;
}

/**
 * The whole resolution for one request, over an injectable reader (the
 * Admin Firestore SDK in production, a fake in tests): validate input, load
 * the order and its store's owner, check eligibility, read the target's
 * phone. Returns exactly `{ phone }` — no name, email, role, uid or address.
 */
export async function resolveOrderContact(
  reader: DocReader,
  callerUid: string,
  data: unknown
): Promise<{ phone: string }> {
  const { orderId, target } = parseContactRequest(data);

  const order = (await reader.collection("orders").doc(orderId).get()).data();
  if (!order) {
    throw new HttpsError("not-found", "Order does not exist.");
  }

  const vendorId = nonEmptyString(order.vendorId);
  const vendorOwnerId = vendorId
    ? nonEmptyString((await reader.collection("vendors").doc(vendorId).get()).data()?.ownerId)
    : null;

  const targetUid = contactTargetUid({ callerUid, target, order, vendorOwnerId });
  const targetUser = (await reader.collection("users").doc(targetUid).get()).data();

  return { phone: phoneFromUser(targetUser) };
}

/**
 * Returns `{ phone }` — only the phone number of the order participant
 * [request.data.target], if the caller may contact them right now.
 */
export const getOrderContact = onCall(async (request) => {
  const callerUid = request.auth?.uid;
  if (!callerUid) {
    throw new HttpsError("unauthenticated", "Must be signed in.");
  }
  return resolveOrderContact(db, callerUid, request.data);
});
