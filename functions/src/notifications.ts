import * as logger from "firebase-functions/logger";

import { db, messaging } from "./admin";

/**
 * Looks up the FCM token stored on a user's document (written by the client
 * after `FirebaseMessaging.instance.getToken()`) and sends a push notification.
 * Silently no-ops if the user has no token registered yet. A send failure
 * (e.g. a stale/uninstalled token) is logged rather than thrown, so it
 * doesn't fail the Firestore trigger that called this.
 */
export async function notifyUser(
  userId: string,
  notification: { title: string; body: string }
): Promise<void> {
  const userDoc = await db.collection("users").doc(userId).get();
  const fcmToken = userDoc.data()?.fcmToken as string | undefined;
  if (!fcmToken) return;

  try {
    await messaging.send({
      token: fcmToken,
      notification,
    });
  } catch (error) {
    logger.warn("notifyUser: failed to send push notification", { userId, error });
  }
}
