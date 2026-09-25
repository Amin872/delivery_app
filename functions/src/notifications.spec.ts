import assert from "node:assert/strict";

import {
  deliverNotification,
  isStaleTokenError,
  NOTIFICATION_TEMPLATES,
  NotificationIntent,
  NotifyDeps,
  orderNotifications,
  renderNotification,
  resolveLocale,
} from "./notifications";

const CUSTOMER = "customer-1";
const OWNER = "vendor-owner-1";
const DRIVER = "driver-1";
const OTHER_DRIVER = "driver-2";
const ORDER = "order-1";

function order(status: string, driverId: string | null = null): Record<string, unknown> {
  return { customerId: CUSTOMER, vendorId: "vendor-1", driverId, status };
}

/** "recipient:template" pairs, sorted, for compact assertions. */
function pairs(intents: NotificationIntent[]): string[] {
  return intents.map((i) => `${i.recipientUid}:${i.template}`).sort();
}

function transition(from: string, to: string, fromDriver: string | null = null, toDriver = fromDriver) {
  return orderNotifications(order(from, fromDriver), order(to, toDriver), ORDER, OWNER);
}

describe("orderNotifications — creation", () => {
  it("a new order notifies the vendor owner", () => {
    assert.deepEqual(orderNotifications(undefined, order("pending"), ORDER, OWNER), [
      { recipientUid: OWNER, template: "vendorNewOrder", orderId: ORDER },
    ]);
  });

  it("no vendor owner -> nothing", () => {
    assert.deepEqual(orderNotifications(undefined, order("pending"), ORDER, null), []);
  });

  it("no after data -> nothing", () => {
    assert.deepEqual(orderNotifications(order("pending"), undefined, ORDER, OWNER), []);
  });
});

describe("orderNotifications — status changes", () => {
  const customerOnly: Array<[string, string, string]> = [
    ["pending", "accepted", "customerAccepted"],
    ["accepted", "preparing", "customerPreparing"],
    ["preparing", "readyForPickup", "customerReadyForPickup"],
  ];
  for (const [from, to, template] of customerOnly) {
    it(`${from} -> ${to} notifies only the customer`, () => {
      assert.deepEqual(pairs(transition(from, to)), [`${CUSTOMER}:${template}`]);
    });
  }

  it("readyForPickup -> driverAssigned (acceptDelivery) notifies customer, vendor and the driver once", () => {
    assert.deepEqual(pairs(transition("readyForPickup", "driverAssigned", null, DRIVER)), [
      `${CUSTOMER}:customerDriverAssigned`,
      `${DRIVER}:driverAssigned`,
      `${OWNER}:vendorDriverAssigned`,
    ]);
  });

  it("driverAssigned -> pickedUp notifies the customer", () => {
    assert.deepEqual(pairs(transition("driverAssigned", "pickedUp", DRIVER)), [`${CUSTOMER}:customerPickedUp`]);
  });

  it("pickedUp -> delivering notifies the customer", () => {
    assert.deepEqual(pairs(transition("pickedUp", "delivering", DRIVER)), [`${CUSTOMER}:customerDelivering`]);
  });

  it("delivering -> delivered notifies customer and vendor", () => {
    assert.deepEqual(pairs(transition("delivering", "delivered", DRIVER)), [
      `${CUSTOMER}:customerDelivered`,
      `${OWNER}:vendorDelivered`,
    ]);
  });

  it("cancelled with a driver notifies customer, vendor and the assigned driver", () => {
    assert.deepEqual(pairs(transition("driverAssigned", "cancelled", DRIVER)), [
      `${CUSTOMER}:orderCancelled`,
      `${DRIVER}:orderCancelled`,
      `${OWNER}:orderCancelled`,
    ]);
  });

  it("cancelled without a driver notifies customer and vendor only (missing driver)", () => {
    assert.deepEqual(pairs(transition("pending", "cancelled")), [
      `${CUSTOMER}:orderCancelled`,
      `${OWNER}:orderCancelled`,
    ]);
  });

  it("missing vendor owner skips the vendor but keeps the others", () => {
    const intents = orderNotifications(order("delivering", DRIVER), order("delivered", DRIVER), ORDER, null);
    assert.deepEqual(pairs(intents), [`${CUSTOMER}:customerDelivered`]);
  });

  it("driverAssigned with no driverId set notifies customer and vendor only", () => {
    assert.deepEqual(pairs(transition("readyForPickup", "driverAssigned")), [
      `${CUSTOMER}:customerDriverAssigned`,
      `${OWNER}:vendorDriverAssigned`,
    ]);
  });
});

describe("orderNotifications — driver reassignment", () => {
  for (const status of ["driverAssigned", "pickedUp"]) {
    it(`reassignment with status unchanged (${status}) notifies the new and previous driver`, () => {
      assert.deepEqual(pairs(transition(status, status, DRIVER, OTHER_DRIVER)), [
        `${DRIVER}:driverReassignedAway`,
        `${OTHER_DRIVER}:driverAssigned`,
      ]);
    });
  }

  it("reassignment that also changes status (readyForPickup -> driverAssigned) has no duplicates", () => {
    const intents = transition("readyForPickup", "driverAssigned", null, OTHER_DRIVER);
    assert.deepEqual(pairs(intents), [
      `${CUSTOMER}:customerDriverAssigned`,
      `${OTHER_DRIVER}:driverAssigned`,
      `${OWNER}:vendorDriverAssigned`,
    ]);
    assert.equal(intents.filter((i) => i.recipientUid === OTHER_DRIVER).length, 1);
  });

  it("no status or driver change produces nothing (e.g. a proof photo landing)", () => {
    assert.deepEqual(transition("delivered", "delivered", DRIVER), []);
    assert.deepEqual(transition("pending", "pending"), []);
  });

  it("every intent carries only recipient, template and orderId", () => {
    for (const intent of transition("delivering", "delivered", DRIVER)) {
      assert.deepEqual(Object.keys(intent).sort(), ["orderId", "recipientUid", "template"]);
      assert.equal(intent.orderId, ORDER);
    }
  });
});

describe("templates, locale and payload", () => {
  const intent: NotificationIntent = { recipientUid: CUSTOMER, template: "customerDriverAssigned", orderId: ORDER };

  it("resolveLocale: 'en' is English; 'ar', missing and invalid are Arabic", () => {
    assert.equal(resolveLocale("en"), "en");
    for (const value of ["ar", undefined, null, "fr", "EN", 1]) {
      assert.equal(resolveLocale(value), "ar", String(value));
    }
  });

  it("renders English text for 'en'", () => {
    const { notification } = renderNotification(intent, "en");
    assert.deepEqual(notification, NOTIFICATION_TEMPLATES.customerDriverAssigned.en);
  });

  it("renders Arabic text for 'ar'", () => {
    const { notification } = renderNotification(intent, "ar");
    assert.deepEqual(notification, NOTIFICATION_TEMPLATES.customerDriverAssigned.ar);
  });

  it("data payload is exactly { type, orderId } with a stable type", () => {
    assert.deepEqual(renderNotification(intent, "ar").data, { type: "order_status", orderId: ORDER });
    assert.deepEqual(
      renderNotification({ recipientUid: OTHER_DRIVER, template: "driverReassignedAway", orderId: ORDER }, "en").data,
      { type: "driver_reassigned", orderId: ORDER }
    );
  });

  it("every template has non-empty Arabic and English text and a known type", () => {
    const types = new Set([
      "order_created",
      "order_status",
      "driver_assigned",
      "order_delivered",
      "order_cancelled",
      "driver_reassigned",
    ]);
    for (const [name, template] of Object.entries(NOTIFICATION_TEMPLATES)) {
      assert.ok(types.has(template.type), name);
      for (const text of [template.ar, template.en]) {
        assert.ok(text.title.length > 0 && text.body.length > 0, name);
      }
    }
  });

  it("no template text contains a raw status enum", () => {
    // The camelCase wire values the old trigger used to send verbatim
    // ("Your order is now driverAssigned."). Plain words such as
    // "preparing" are fine in English prose.
    const raw = ["driverAssigned", "readyForPickup", "pickedUp"];
    for (const template of Object.values(NOTIFICATION_TEMPLATES)) {
      for (const text of [template.ar, template.en]) {
        for (const value of raw) {
          assert.ok(!`${text.title} ${text.body}`.includes(value), value);
        }
      }
    }
  });
});

describe("deliverNotification (the notifyUser path)", () => {
  const intent: NotificationIntent = { recipientUid: CUSTOMER, template: "customerDelivered", orderId: ORDER };

  function deps(user: Record<string, unknown> | undefined, sendResult?: Error) {
    const sent: unknown[] = [];
    const cleared: Array<[string, string]> = [];
    const d: NotifyDeps = {
      getUser: async () => user,
      send: async (message) => {
        sent.push(message);
        if (sendResult) throw sendResult;
        return "message-id";
      },
      clearToken: async (uid, token) => {
        cleared.push([uid, token]);
      },
    };
    return { d, sent, cleared };
  }

  function fcmError(code: string): Error {
    return Object.assign(new Error(code), { code });
  }

  it("sends to the user's token in their locale, with the data payload", async () => {
    const { d, sent } = deps({ fcmToken: "tok-1", locale: "en" });

    assert.equal(await deliverNotification(d, intent), "sent");
    assert.deepEqual(sent, [
      {
        token: "tok-1",
        notification: NOTIFICATION_TEMPLATES.customerDelivered.en,
        data: { type: "order_delivered", orderId: ORDER },
      },
    ]);
  });

  it("defaults to Arabic when the user has no locale", async () => {
    const { d, sent } = deps({ fcmToken: "tok-1" });

    await deliverNotification(d, intent);
    assert.deepEqual((sent[0] as { notification: unknown }).notification, NOTIFICATION_TEMPLATES.customerDelivered.ar);
  });

  it("no token (or no user) is a silent no-op", async () => {
    for (const user of [undefined, {}, { fcmToken: "" }]) {
      const { d, sent } = deps(user);
      assert.equal(await deliverNotification(d, intent), "no-token");
      assert.equal(sent.length, 0);
    }
  });

  for (const code of ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"]) {
    it(`clears the stale token on ${code}, without throwing`, async () => {
      const { d, cleared } = deps({ fcmToken: "tok-old" }, fcmError(code));

      assert.equal(await deliverNotification(d, intent), "stale-token-cleared");
      assert.deepEqual(cleared, [[CUSTOMER, "tok-old"]]);
    });
  }

  for (const code of ["messaging/internal-error", "messaging/server-unavailable", "messaging/quota-exceeded"]) {
    it(`a transient error (${code}) keeps the token and doesn't throw`, async () => {
      const { d, cleared } = deps({ fcmToken: "tok-1" }, fcmError(code));

      assert.equal(await deliverNotification(d, intent), "failed");
      assert.deepEqual(cleared, []);
    });
  }

  it("a failure reading the user doesn't throw", async () => {
    const d: NotifyDeps = {
      getUser: async () => {
        throw new Error("firestore down");
      },
      send: async () => "x",
      clearToken: async () => undefined,
    };
    assert.equal(await deliverNotification(d, intent), "failed");
  });

  it("isStaleTokenError only matches the permanent FCM codes", () => {
    assert.equal(isStaleTokenError(fcmError("messaging/registration-token-not-registered")), true);
    assert.equal(isStaleTokenError(fcmError("messaging/internal-error")), false);
    assert.equal(isStaleTokenError(new Error("no code")), false);
    assert.equal(isStaleTokenError(null), false);
  });
});
