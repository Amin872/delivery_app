import * as logger from "firebase-functions/logger";
import { FieldValue } from "firebase-admin/firestore";

import { db, messaging } from "./admin";

// Order push notifications: WHAT to send (orderNotifications, a pure event
// planner over an order's before/after state), HOW it reads (bilingual
// templates picked by users/{uid}.locale), and the single sender
// (notifyUser) that looks up the recipient's one fcmToken on users/{uid}.
// The order triggers in orders.ts are the only callers.

/** Stable values for the FCM data payload's `type` (client tap routing). */
export type NotificationType =
  | "order_created"
  | "order_status"
  | "driver_assigned"
  | "order_delivered"
  | "order_cancelled"
  | "driver_reassigned";

export type NotificationTemplate =
  | "vendorNewOrder"
  | "customerAccepted"
  | "customerPreparing"
  | "customerReadyForPickup"
  | "customerDriverAssigned"
  | "customerPickedUp"
  | "customerDelivering"
  | "customerDelivered"
  | "vendorDriverAssigned"
  | "vendorDelivered"
  | "driverAssigned"
  | "driverReassignedAway"
  | "orderCancelled";

type MessageText = { title: string; body: string };

/** Every template's type and its Arabic + English text, in one place. */
export const NOTIFICATION_TEMPLATES: Record<
  NotificationTemplate,
  { type: NotificationType; ar: MessageText; en: MessageText }
> = {
  vendorNewOrder: {
    type: "order_created",
    en: { title: "New order", body: "You have a new order waiting for confirmation." },
    ar: { title: "طلب جديد", body: "لديك طلب جديد بانتظار التأكيد." },
  },
  customerAccepted: {
    type: "order_status",
    en: { title: "Order accepted", body: "The store accepted your order." },
    ar: { title: "تم قبول الطلب", body: "قبل المتجر طلبك." },
  },
  customerPreparing: {
    type: "order_status",
    en: { title: "Preparing your order", body: "The store is preparing your order." },
    ar: { title: "جارٍ تحضير طلبك", body: "يقوم المتجر بتحضير طلبك." },
  },
  customerReadyForPickup: {
    type: "order_status",
    en: { title: "Order ready", body: "Your order is ready and waiting for a driver." },
    ar: { title: "الطلب جاهز", body: "طلبك جاهز وبانتظار سائق." },
  },
  customerDriverAssigned: {
    type: "order_status",
    en: { title: "Driver assigned", body: "A driver is on the way to pick up your order." },
    ar: { title: "تم تعيين سائق", body: "السائق في طريقه لاستلام طلبك." },
  },
  customerPickedUp: {
    type: "order_status",
    en: { title: "Order picked up", body: "The driver has picked up your order." },
    ar: { title: "تم استلام الطلب", body: "استلم السائق طلبك." },
  },
  customerDelivering: {
    type: "order_status",
    en: { title: "On the way", body: "Your order is on its way to you." },
    ar: { title: "في الطريق إليك", body: "طلبك في الطريق إليك." },
  },
  customerDelivered: {
    type: "order_delivered",
    en: { title: "Order delivered", body: "Your order has been delivered. Enjoy!" },
    ar: { title: "تم توصيل الطلب", body: "تم توصيل طلبك. بالهناء!" },
  },
  vendorDriverAssigned: {
    type: "driver_assigned",
    en: { title: "Driver assigned", body: "A driver is coming to pick up an order." },
    ar: { title: "تم تعيين سائق", body: "سائق في طريقه لاستلام أحد الطلبات." },
  },
  vendorDelivered: {
    type: "order_delivered",
    en: { title: "Order delivered", body: "One of your orders has been delivered." },
    ar: { title: "تم توصيل الطلب", body: "تم توصيل أحد طلباتك." },
  },
  driverAssigned: {
    type: "driver_assigned",
    en: { title: "New delivery", body: "An order has been assigned to you." },
    ar: { title: "توصيلة جديدة", body: "تم تعيين طلب لك." },
  },
  driverReassignedAway: {
    type: "driver_reassigned",
    en: { title: "Order reassigned", body: "An order has been reassigned to another driver." },
    ar: { title: "تمت إعادة تعيين الطلب", body: "تمت إعادة تعيين أحد الطلبات إلى سائق آخر." },
  },
  orderCancelled: {
    type: "order_cancelled",
    en: { title: "Order cancelled", body: "An order has been cancelled." },
    ar: { title: "تم إلغاء الطلب", body: "تم إلغاء أحد الطلبات." },
  },
};

/** One push to one user. Deliberately carries nothing else about anyone. */
export interface NotificationIntent {
  recipientUid: string;
  template: NotificationTemplate;
  orderId: string;
}

type OrderData = Record<string, unknown> | undefined;

function uidOrNull(value: unknown): string | null {
  return typeof value === "string" && value.length > 0 ? value : null;
}

/**
 * The notifications one order write should produce. [before] undefined =
 * the order was just created. [vendorOwnerId] is vendors/{vendorId}.ownerId
 * (null skips the vendor). Nothing is produced when neither the status nor
 * the assigned driver changed, and the same (recipient, template) pair is
 * never listed twice — e.g. acceptDelivery both sets driverAssigned and
 * sets driverId, but the driver still gets one "assigned" push.
 */
export function orderNotifications(
  before: OrderData,
  after: OrderData,
  orderId: string,
  vendorOwnerId: string | null
): NotificationIntent[] {
  if (!after) return [];
  const intents: NotificationIntent[] = [];
  const add = (recipientUid: string | null, template: NotificationTemplate) => {
    if (!recipientUid) return;
    if (intents.some((i) => i.recipientUid === recipientUid && i.template === template)) return;
    intents.push({ recipientUid, template, orderId });
  };

  const customer = uidOrNull(after.customerId);
  const driver = uidOrNull(after.driverId);

  if (!before) {
    add(vendorOwnerId, "vendorNewOrder");
    return intents;
  }

  const previousDriver = uidOrNull(before.driverId);
  const statusChanged = before.status !== after.status;
  const driverChanged = previousDriver !== driver;

  if (statusChanged) {
    switch (after.status) {
      case "accepted":
        add(customer, "customerAccepted");
        break;
      case "preparing":
        add(customer, "customerPreparing");
        break;
      case "readyForPickup":
        add(customer, "customerReadyForPickup");
        break;
      case "driverAssigned":
        add(customer, "customerDriverAssigned");
        add(vendorOwnerId, "vendorDriverAssigned");
        add(driver, "driverAssigned");
        break;
      case "pickedUp":
        add(customer, "customerPickedUp");
        break;
      case "delivering":
        add(customer, "customerDelivering");
        break;
      case "delivered":
        add(customer, "customerDelivered");
        add(vendorOwnerId, "vendorDelivered");
        break;
      case "cancelled":
        add(customer, "orderCancelled");
        add(vendorOwnerId, "orderCancelled");
        add(driver, "orderCancelled");
        break;
    }
  }

  if (driverChanged) {
    add(driver, "driverAssigned");
    add(previousDriver, "driverReassignedAway");
  }

  return intents;
}

/** users/{uid}.locale -> template language; anything but 'en' is Arabic. */
export function resolveLocale(value: unknown): "ar" | "en" {
  return value === "en" ? "en" : "ar";
}

/** The FCM message body for [intent] in [locale] (no token). */
export function renderNotification(
  intent: NotificationIntent,
  locale: "ar" | "en"
): { notification: MessageText; data: { type: NotificationType; orderId: string } } {
  const template = NOTIFICATION_TEMPLATES[intent.template];
  return {
    notification: { ...template[locale] },
    data: { type: template.type, orderId: intent.orderId },
  };
}

// FCM error codes meaning the stored token will never work again; anything
// else (quota, network, server) is transient and leaves the token alone.
const STALE_TOKEN_ERRORS = new Set([
  "messaging/registration-token-not-registered",
  "messaging/invalid-registration-token",
]);

export function isStaleTokenError(error: unknown): boolean {
  const code = (error as { code?: unknown } | null)?.code;
  return typeof code === "string" && STALE_TOKEN_ERRORS.has(code);
}

/** What notifyUser needs from Firestore/FCM — injectable for tests. */
export interface NotifyDeps {
  getUser(uid: string): Promise<Record<string, unknown> | undefined>;
  send(message: {
    token: string;
    notification: MessageText;
    data: { type: NotificationType; orderId: string };
  }): Promise<unknown>;
  clearToken(uid: string, staleToken: string): Promise<void>;
}

/**
 * Sends [intent] to its recipient's fcmToken in their locale. No token = a
 * silent no-op. Never throws, so one bad token can't fail an order
 * trigger: a stale token is cleared, any other failure is only logged.
 * Returns what happened, for tests and logs.
 */
export async function deliverNotification(
  deps: NotifyDeps,
  intent: NotificationIntent
): Promise<"sent" | "no-token" | "stale-token-cleared" | "failed"> {
  try {
    const user = await deps.getUser(intent.recipientUid);
    const token = typeof user?.fcmToken === "string" && user.fcmToken.length > 0 ? user.fcmToken : null;
    if (!token) return "no-token";

    try {
      await deps.send({ token, ...renderNotification(intent, resolveLocale(user?.locale)) });
      return "sent";
    } catch (error) {
      if (isStaleTokenError(error)) {
        await deps.clearToken(intent.recipientUid, token);
        logger.info("notifyUser: cleared a stale FCM token", { userId: intent.recipientUid });
        return "stale-token-cleared";
      }
      logger.warn("notifyUser: failed to send push notification", { userId: intent.recipientUid, error });
      return "failed";
    }
  } catch (error) {
    logger.warn("notifyUser: failed to prepare push notification", { userId: intent.recipientUid, error });
    return "failed";
  }
}

const firestoreDeps: NotifyDeps = {
  getUser: async (uid) => (await db.collection("users").doc(uid).get()).data(),
  send: (message) => messaging.send(message),
  // Transactional so a token the user registered after the failed send
  // (e.g. on a new device) isn't wiped by mistake.
  clearToken: (uid, staleToken) =>
    db.runTransaction(async (transaction) => {
      const ref = db.collection("users").doc(uid);
      const snap = await transaction.get(ref);
      if (snap.data()?.fcmToken === staleToken) {
        transaction.update(ref, { fcmToken: FieldValue.delete() });
      }
    }),
};

/** The one push sender. See [deliverNotification]. */
export async function notifyUser(intent: NotificationIntent): Promise<void> {
  await deliverNotification(firestoreDeps, intent);
}
