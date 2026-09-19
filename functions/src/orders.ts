import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { FieldValue } from "firebase-admin/firestore";

import { db } from "./admin";
import { assertIsAdmin, assertIsDriver } from "./auth";
import { notifyUser } from "./notifications";

export const onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data?.data();
  if (!order) return;

  const vendorDoc = await db.collection("vendors").doc(order.vendorId).get();
  const ownerId = vendorDoc.data()?.ownerId as string | undefined;
  if (!ownerId) {
    logger.warn("onOrderCreated: vendor doc or ownerId missing, skipping notification", {
      orderId: event.params.orderId,
      vendorId: order.vendorId,
    });
    return;
  }

  await notifyUser(ownerId, {
    title: "New order received",
    body: `Order ${event.params.orderId} is waiting for confirmation.`,
  });
});

/**
 * Computes the per-menu-item orderCount increments for a just-delivered
 * order — quantity per item, since a customer might order 3x of the same
 * dish in one order. Pure/exported for unit testing, same split as
 * `nextDeliveryStatus`: the actual decision logic is testable without a
 * Firestore instance, leaving the trigger below as a thin wrapper.
 */
export function menuItemOrderCountIncrements(order: {
  items?: Array<{ menuItemId?: string; quantity?: number }>;
}): Array<{ menuItemId: string; incrementBy: number }> {
  return (order.items ?? [])
    .filter((item): item is { menuItemId: string; quantity?: number } => !!item.menuItemId)
    .map((item) => ({ menuItemId: item.menuItemId, incrementBy: item.quantity ?? 1 }));
}

export const onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.status === after.status) return;

  await notifyUser(after.customerId, {
    title: "Order update",
    body: `Your order is now ${after.status}.`,
  });

  // Aggregates "most ordered" onto each menu item — mirrors onReviewCreated's
  // FieldValue.increment pattern in reviews.ts, one level deeper (the
  // vendor's menuItems subcollection instead of the vendor doc itself).
  // Delivered only, not creation, so a cancelled order never inflates a
  // dish's popularity.
  if (after.status === "delivered") {
    const increments = menuItemOrderCountIncrements(after);
    await Promise.all(
      increments.map(({ menuItemId, incrementBy }) =>
        db
          .collection("vendors")
          .doc(after.vendorId)
          .collection("menuItems")
          .doc(menuItemId)
          .update({ orderCount: FieldValue.increment(incrementBy) })
      )
    );
  }
});

/**
 * Atomically assigns the calling driver to an order, so two drivers racing
 * to accept the same "readyForPickup" order can't both win it.
 */
export const acceptDelivery = onCall(async (request) => {
  const driverUid = request.auth?.uid;
  if (!driverUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as a driver.");
  }

  const orderId = request.data?.orderId as string | undefined;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }

  await assertIsDriver(db, driverUid);

  const orderRef = db.collection("orders").doc(orderId);

  await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    const order = orderSnap.data();

    if (!order) {
      throw new HttpsError("not-found", "Order does not exist.");
    }
    if (order.status !== "readyForPickup" || order.driverId) {
      throw new HttpsError(
        "failed-precondition",
        "Order has already been accepted by another driver."
      );
    }

    transaction.update(orderRef, {
      driverId: driverUid,
      status: "pickedUp",
    });
  });

  return { orderId, driverId: driverUid };
});

// The only two forward transitions a driver drives once acceptDelivery has
// already moved the order to "pickedUp" — nothing else (not yet picked up,
// already delivered, cancelled) has a next step here.
const DRIVER_PROGRESSION: Record<string, string> = {
  pickedUp: "delivering",
  delivering: "delivered",
};

/**
 * Resolves the next status for an order once its assigned driver calls
 * `advanceDelivery`, or throws the `HttpsError` that call should surface.
 * Split out from the transaction body so it's testable without a Firestore
 * instance — same reasoning as `assertIsDriver` in auth.ts.
 */
export function nextDeliveryStatus(
  order: { status?: string; driverId?: string } | undefined,
  driverUid: string
): string {
  if (!order) {
    throw new HttpsError("not-found", "Order does not exist.");
  }
  if (order.driverId !== driverUid) {
    throw new HttpsError("permission-denied", "You are not assigned to this order.");
  }
  const next = DRIVER_PROGRESSION[order.status ?? ""];
  if (!next) {
    throw new HttpsError(
      "failed-precondition",
      "Order cannot be advanced from its current status."
    );
  }
  return next;
}

/**
 * Atomically advances the calling driver's assigned order to its next
 * status (pickedUp -> delivering -> delivered). Driver-initiated order
 * writes go through a callable rather than a client-side Firestore rule —
 * see the architecture note in CLAUDE.md — so this is the only path past
 * "pickedUp".
 */
export const advanceDelivery = onCall(async (request) => {
  const driverUid = request.auth?.uid;
  if (!driverUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as a driver.");
  }

  const orderId = request.data?.orderId as string | undefined;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }
  // Optional: the download URL of a proof-of-delivery photo the driver
  // already uploaded to storage.rules' orderProofs/{orderId} path (a direct
  // client write the driver is independently allowed to make). Only stored
  // when this call actually lands the order on "delivered" — attaching it
  // to an earlier transition wouldn't mean anything.
  const proofImageUrl = request.data?.proofImageUrl as string | undefined;

  const orderRef = db.collection("orders").doc(orderId);

  const status = await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    const next = nextDeliveryStatus(orderSnap.data(), driverUid);
    const update: Record<string, unknown> = { status: next };
    if (next === "delivered" && proofImageUrl) {
      update.proofImageUrl = proofImageUrl;
    }
    transaction.update(orderRef, update);
    return next;
  });

  return { orderId, status };
});

// Orders past this point are already committed to a driver's physical
// route (pickedUp/delivering) or already terminal (delivered/cancelled) —
// force-cancelling those would strand an in-progress delivery or rewrite
// history, so only pre-dispatch statuses are admin-cancellable.
const ADMIN_CANCELLABLE_STATUSES = new Set([
  "pending",
  "accepted",
  "preparing",
  "readyForPickup",
]);

/**
 * Throws the `HttpsError` `adminCancelOrder` should surface if [order]
 * isn't in an admin-cancellable status, or does nothing if it is. Split out
 * from the transaction body so it's testable without a Firestore instance —
 * same reasoning as `nextDeliveryStatus` above.
 */
export function assertAdminCancellable(order: { status?: string } | undefined): void {
  if (!order) {
    throw new HttpsError("not-found", "Order does not exist.");
  }
  if (!ADMIN_CANCELLABLE_STATUSES.has(order.status ?? "")) {
    throw new HttpsError(
      "failed-precondition",
      "Order cannot be cancelled from its current status."
    );
  }
}

/**
 * Atomically force-cancels an order on an admin's behalf. Admin-initiated
 * order writes go through a callable rather than a client-side Firestore
 * rule — see the architecture note in CLAUDE.md for why race-sensitive
 * state changes never get a relaxed client rule — so this is the only path
 * to an admin cancellation. Re-checks eligibility inside the transaction
 * (not just via `assertAdminCancellable` at call time) so a concurrent
 * status change (e.g. a driver picking the order up) loses cleanly.
 */
export const adminCancelOrder = onCall(async (request) => {
  const adminUid = request.auth?.uid;
  if (!adminUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as an admin.");
  }

  const orderId = request.data?.orderId as string | undefined;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }

  await assertIsAdmin(db, adminUid);

  const orderRef = db.collection("orders").doc(orderId);

  await db.runTransaction(async (transaction) => {
    const orderSnap = await transaction.get(orderRef);
    assertAdminCancellable(orderSnap.data());
    transaction.update(orderRef, { status: "cancelled" });
  });

  return { orderId, status: "cancelled" };
});

// Reassignment before a driver has picked up (readyForPickup) simply
// (re)assigns who will collect it — no work is undone. Reassignment once
// picked up (pickedUp) swaps who's currently attributed the delivery before
// they've physically left with it. Once a driver is actually en route
// (delivering) or the order is terminal (delivered/cancelled), swapping the
// driver would misrepresent who physically holds the order — mid-delivery
// reassignment is a deliberately separate, not-yet-built feature.
const ADMIN_REASSIGNABLE_STATUSES = new Set(["readyForPickup", "pickedUp"]);

/**
 * Throws the `HttpsError` `adminReassignDriver` should surface if [order]
 * isn't in an admin-reassignable status, or does nothing if it is. Split
 * out from the transaction body for the same reason as
 * `assertAdminCancellable` above.
 */
export function assertAdminReassignable(order: { status?: string } | undefined): void {
  if (!order) {
    throw new HttpsError("not-found", "Order does not exist.");
  }
  if (!ADMIN_REASSIGNABLE_STATUSES.has(order.status ?? "")) {
    throw new HttpsError(
      "failed-precondition",
      "Order cannot be reassigned from its current status."
    );
  }
}

/**
 * Throws the `HttpsError` `adminReassignDriver` should surface if the
 * reassignment target isn't a valid driver, or does nothing if they are.
 * Takes already-fetched user data (rather than a uid) so the check can run
 * inside the same transaction that reads the order — the target's role
 * must be re-verified transactionally, not just checked ahead of time —
 * and so it's testable without a Firestore instance.
 */
export function assertValidReassignmentTarget(targetUser: { role?: string } | undefined): void {
  if (!targetUser) {
    throw new HttpsError("not-found", "Target driver account does not exist.");
  }
  if (targetUser.role !== "driver") {
    throw new HttpsError("failed-precondition", "Target user is not a driver.");
  }
}

/**
 * Atomically reassigns an order to a different driver on an admin's
 * behalf. Verifies both the order's status and the target account's role
 * inside the same transaction that performs the write, so a concurrent
 * status change or an invalid target both lose cleanly rather than
 * producing an inconsistent order. See CLAUDE.md's driver-assignment note
 * for why this is a callable rather than a relaxed client rule.
 */
export const adminReassignDriver = onCall(async (request) => {
  const adminUid = request.auth?.uid;
  if (!adminUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as an admin.");
  }

  const orderId = request.data?.orderId as string | undefined;
  const driverId = request.data?.driverId as string | undefined;
  if (!orderId) {
    throw new HttpsError("invalid-argument", "orderId is required.");
  }
  if (!driverId) {
    throw new HttpsError("invalid-argument", "driverId is required.");
  }

  await assertIsAdmin(db, adminUid);

  const orderRef = db.collection("orders").doc(orderId);
  const targetUserRef = db.collection("users").doc(driverId);

  await db.runTransaction(async (transaction) => {
    const [orderSnap, targetUserSnap] = await Promise.all([
      transaction.get(orderRef),
      transaction.get(targetUserRef),
    ]);
    assertAdminReassignable(orderSnap.data());
    assertValidReassignmentTarget(targetUserSnap.data());
    transaction.update(orderRef, { driverId });
  });

  return { orderId, driverId };
});
