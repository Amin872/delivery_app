import { onDocumentCreated, onDocumentUpdated } from "firebase-functions/v2/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { FieldValue } from "firebase-admin/firestore";

import { db } from "./admin";
import {
  assertDriverAvailable,
  assertIsAdmin,
  assertIsApprovedDriver,
  isApprovedDriverDoc,
  requireDocId,
} from "./auth";
import { notifyUser, orderNotifications } from "./notifications";

/** vendors/{vendorId}.ownerId — the store owner who receives vendor pushes. */
async function vendorOwnerOf(vendorId: unknown): Promise<string | null> {
  if (typeof vendorId !== "string" || vendorId.length === 0) return null;
  const ownerId = (await db.collection("vendors").doc(vendorId).get()).data()?.ownerId;
  return typeof ownerId === "string" && ownerId.length > 0 ? ownerId : null;
}

export const onOrderCreated = onDocumentCreated("orders/{orderId}", async (event) => {
  const order = event.data?.data();
  if (!order) return;

  const ownerId = await vendorOwnerOf(order.vendorId);
  if (!ownerId) {
    logger.warn("onOrderCreated: vendor doc or ownerId missing, skipping notification", {
      orderId: event.params.orderId,
      vendorId: order.vendorId,
    });
    return;
  }

  const intents = orderNotifications(undefined, order, event.params.orderId, ownerId);
  await Promise.all(intents.map((intent) => notifyUser(intent)));
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
  if (!before || !after) return;

  // A status change, or a driver change with the status left as is (admin
  // reassignment of a driverAssigned/pickedUp order), is worth a push;
  // anything else (e.g. a proof photo URL landing) isn't.
  const statusChanged = before.status !== after.status;
  const driverChanged = (before.driverId ?? null) !== (after.driverId ?? null);
  if (!statusChanged && !driverChanged) return;

  const vendorOwnerId = statusChanged ? await vendorOwnerOf(after.vendorId) : null;
  const intents = orderNotifications(before, after, event.params.orderId, vendorOwnerId);
  await Promise.all(intents.map((intent) => notifyUser(intent)));

  // Aggregates "most ordered" onto each menu item — mirrors onReviewCreated's
  // FieldValue.increment pattern in reviews.ts, one level deeper (the
  // vendor's menuItems subcollection instead of the vendor doc itself).
  // Delivered only, not creation, so a cancelled order never inflates a
  // dish's popularity.
  if (statusChanged && after.status === "delivered") {
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
 * to accept the same "readyForPickup" order can't both win it. Lands the
 * order on "driverAssigned" — Phase 4's addition marking "a driver has
 * claimed this but hasn't physically collected it from the vendor yet" —
 * rather than jumping straight to "pickedUp" as this callable did before
 * Phase 4. The driver's own subsequent physical-pickup confirmation goes
 * through `advanceDelivery` below, same callable that already drives every
 * later transition.
 */
export const acceptDelivery = onCall(async (request) => {
  const driverUid = request.auth?.uid;
  if (!driverUid) {
    throw new HttpsError("unauthenticated", "Must be signed in as a driver.");
  }

  const orderId = requireDocId(request.data?.orderId, "orderId");

  // Only an admin-approved driver who has switched themselves available may
  // claim new work.
  const driver = await assertIsApprovedDriver(db, driverUid);
  assertDriverAvailable(driver);

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
      status: "driverAssigned",
    });
  });

  return { orderId, driverId: driverUid };
});

// The forward transitions a driver drives once acceptDelivery has already
// moved the order to "driverAssigned" — nothing else (not yet assigned,
// already delivered, cancelled) has a next step here. "driverAssigned" ->
// "pickedUp" is the driver confirming physical collection from the vendor
// (Phase 4 addition); "pickedUp" -> "delivering" -> "delivered" are
// unchanged from before Phase 4.
/** Upper bound on a proof value; a real download URL is ~200 characters. */
export const MAX_PROOF_IMAGE_URL_LENGTH = 2048;

const FIREBASE_STORAGE_HOST = "firebasestorage.googleapis.com";

/** The one Storage object a delivery's proof may be: what
 * StorageService.uploadOrderProof writes and storage.rules allows. */
export function proofObjectPath(orderId: string): string {
  return `orderProofs/${orderId}/proof.jpg`;
}

/** The project's default Storage bucket, from the FIREBASE_CONFIG the
 * Functions runtime (and emulator) provides; null when unknown, which
 * makes every download-URL proof fail closed. */
export function defaultStorageBucket(): string | null {
  try {
    const bucket = JSON.parse(process.env.FIREBASE_CONFIG ?? "{}").storageBucket;
    return typeof bucket === "string" && bucket.length > 0 ? bucket : null;
  } catch {
    return null;
  }
}

/**
 * Validates advanceDelivery's optional `proofImageUrl` for [orderId] and
 * returns the value to store, or null when none was given (undefined, null
 * or "" — proof stays optional, as before).
 *
 * Accepted, and returned unchanged:
 * - the canonical object path `orderProofs/{orderId}/proof.jpg`;
 * - a Firebase Storage download URL for exactly that object in [bucket] —
 *   what `getDownloadURL()` returns and the apps render:
 *   `https://firebasestorage.googleapis.com/v0/b/{bucket}/o/orderProofs%2F{orderId}%2Fproof.jpg?alt=media[&token=…]`.
 *   The whole URL must already be in canonical form (so dot segments or
 *   other normalisation can't smuggle in a different object), carry no
 *   credentials, port or fragment, and no query parameters beyond `alt`
 *   (= media) and `token`.
 *
 * Everything else — other orders' proofs, other file names or buckets,
 * external hosts, traversal, non-strings, over-long values — is an
 * `invalid-argument` error. [allowEmulatorHost] relaxes ONLY the
 * scheme/host check (for the local Storage emulator's http://host:port
 * URLs); bucket and object path are still checked exactly.
 */
export function validateProofImageUrl(
  value: unknown,
  orderId: string,
  options: { bucket: string | null; allowEmulatorHost?: boolean }
): string | null {
  if (value === undefined || value === null || value === "") return null;

  const invalid = () =>
    new HttpsError("invalid-argument", "proofImageUrl must be this order's uploaded proof photo.");

  if (typeof value !== "string" || value.length > MAX_PROOF_IMAGE_URL_LENGTH) throw invalid();

  const objectPath = proofObjectPath(orderId);
  if (value === objectPath) return value;

  let url: URL;
  try {
    url = new URL(value);
  } catch {
    throw invalid();
  }
  // Any normalisation (dot segments, case, encoding) means the string isn't
  // the canonical URL of a single object.
  if (url.href !== value) throw invalid();

  const productionHost =
    url.protocol === "https:" && url.hostname === FIREBASE_STORAGE_HOST && url.port === "";
  const emulatorHost = options.allowEmulatorHost === true && (url.protocol === "http:" || url.protocol === "https:");
  if (!productionHost && !emulatorHost) throw invalid();
  if (url.username !== "" || url.password !== "" || url.hash !== "") throw invalid();

  const match = /^\/v0\/b\/([^/]+)\/o\/([^/]+)$/.exec(url.pathname);
  if (!match) throw invalid();
  let object: string;
  try {
    object = decodeURIComponent(match[2]);
  } catch {
    throw invalid();
  }
  if (options.bucket === null || match[1] !== options.bucket || object !== objectPath) throw invalid();

  for (const key of url.searchParams.keys()) {
    if (key !== "alt" && key !== "token") throw invalid();
  }
  if (url.searchParams.getAll("alt").join() !== "media" || url.searchParams.getAll("token").length > 1) {
    throw invalid();
  }
  return value;
}

const DRIVER_PROGRESSION: Record<string, string> = {
  driverAssigned: "pickedUp",
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

  const orderId = requireDocId(request.data?.orderId, "orderId");
  // Optional: the download URL of a proof-of-delivery photo the driver
  // already uploaded to storage.rules' orderProofs/{orderId} path (a direct
  // client write the driver is independently allowed to make). Only stored
  // when this call actually lands the order on "delivered" — attaching it
  // to an earlier transition wouldn't mean anything. Validated (Phase 31
  // H3) before the order is touched: it must be THIS order's proof object,
  // never an arbitrary or external URL.
  const proofImageUrl = validateProofImageUrl(request.data?.proofImageUrl, orderId, {
    bucket: defaultStorageBucket(),
    allowEmulatorHost: process.env.FUNCTIONS_EMULATOR === "true",
  });

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

  const orderId = requireDocId(request.data?.orderId, "orderId");

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
// (re)assigns who will collect it — no work is undone. Reassignment once a
// driver has claimed but not yet physically collected the order
// (driverAssigned, Phase 4 addition) or has already picked it up (pickedUp)
// swaps who's currently attributed the delivery before/just as they take
// physical hold of it. Once a driver is actually en route (delivering) or
// the order is terminal (delivered/cancelled), swapping the driver would
// misrepresent who physically holds the order — mid-delivery reassignment
// is a deliberately separate, not-yet-built feature.
const ADMIN_REASSIGNABLE_STATUSES = new Set(["readyForPickup", "driverAssigned", "pickedUp"]);

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
 * Throws the `HttpsError` `adminReassignDriver` should surface unless the
 * target's drivers/{uid} doc is admin-approved (missing doc/field counts
 * as not approved). Checked alongside [assertValidReassignmentTarget],
 * inside the same transaction, so an unapproved driver can never be handed
 * an order they couldn't have accepted themselves.
 */
export function assertApprovedReassignmentTarget(
  targetDriver: { approvalStatus?: unknown } | undefined
): void {
  if (!isApprovedDriverDoc(targetDriver)) {
    throw new HttpsError("failed-precondition", "Target driver is not approved.");
  }
}

/**
 * Computes the Firestore update `adminReassignDriver` should apply, given
 * the order's current [orderStatus]. Always sets `driverId`. Additionally
 * advances `status` to "driverAssigned" when [orderStatus] is
 * "readyForPickup" — reassigning an order that had no driver yet is really
 * a first assignment, not a driver swap, so it must land on the same
 * status `acceptDelivery` itself would produce. Without this, the order
 * would keep `driverId` set but `status` stuck on "readyForPickup":
 * invisible to the assigned driver's own `watchActiveDriverOrder` (which
 * only matches driverAssigned/pickedUp/delivering) and no longer in the
 * unclaimed queue either (which requires `driverId == null`) — an orphaned
 * state. For "driverAssigned"/"pickedUp" starting statuses this is a pure
 * driver swap — status is already correct and must stay untouched. Split
 * out from the transaction body so it's testable without a Firestore
 * instance — same reasoning as `nextDeliveryStatus` above.
 */
export function reassignmentUpdate(
  orderStatus: string | undefined,
  driverId: string
): Record<string, unknown> {
  const update: Record<string, unknown> = { driverId };
  if (orderStatus === "readyForPickup") {
    update.status = "driverAssigned";
  }
  return update;
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

  const orderId = requireDocId(request.data?.orderId, "orderId");
  const driverId = requireDocId(request.data?.driverId, "driverId");

  await assertIsAdmin(db, adminUid);

  const orderRef = db.collection("orders").doc(orderId);
  const targetUserRef = db.collection("users").doc(driverId);
  const targetDriverRef = db.collection("drivers").doc(driverId);

  await db.runTransaction(async (transaction) => {
    const [orderSnap, targetUserSnap, targetDriverSnap] = await Promise.all([
      transaction.get(orderRef),
      transaction.get(targetUserRef),
      transaction.get(targetDriverRef),
    ]);
    assertAdminReassignable(orderSnap.data());
    assertValidReassignmentTarget(targetUserSnap.data());
    assertApprovedReassignmentTarget(targetDriverSnap.data());
    transaction.update(orderRef, reassignmentUpdate(orderSnap.data()?.status, driverId));
  });

  return { orderId, driverId };
});
