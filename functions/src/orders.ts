import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { db } from "./admin";
import { notifyUser } from "./notifications";

export const onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data?.data();
  if (!order) return;

  const vendorDoc = await db.collection("vendors").doc(order.vendorId).get();
  const ownerId = vendorDoc.data()?.ownerId as string | undefined;
  if (!ownerId) return;

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
