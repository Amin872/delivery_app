import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

import { db } from "./admin";
import { assertIsDriver } from "./auth";
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

export const onOrderStatusChanged = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before.data();
  const after = event.data?.after.data();
  if (!before || !after || before.status === after.status) return;

  await notifyUser(after.customerId, {
    title: "Order update",
    body: `Your order is now ${after.status}.`,
  });
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
