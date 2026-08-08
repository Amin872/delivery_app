import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { FieldValue } from "firebase-admin/firestore";

import { db } from "./admin";

/**
 * Aggregates a newly-created review into the vendor's and driver's running
 * rating totals. `FieldValue.increment` on both docs is enough on its own —
 * no transaction needed, unlike `acceptDelivery` — because increments are
 * commutative and don't require reading the current value first, and each
 * review can only be created once (see the `reviews/{orderId}` create rule
 * in firestore.rules, keyed on the order id so a customer can't submit a
 * second review for the same order to inflate a rating twice).
 */
export const onReviewCreated = onDocumentCreated("reviews/{orderId}", async (event) => {
  const review = event.data?.data();
  if (!review) return;

  await Promise.all([
    db.collection("vendors").doc(review.vendorId).update({
      ratingSum: FieldValue.increment(review.vendorRating),
      ratingCount: FieldValue.increment(1),
    }),
    db.collection("drivers").doc(review.driverId).update({
      ratingSum: FieldValue.increment(review.driverRating),
      ratingCount: FieldValue.increment(1),
    }),
  ]);
});
