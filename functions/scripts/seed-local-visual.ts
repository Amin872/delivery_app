/**
 * Seeds a small, fixed data set into the local Firebase *emulators* (never
 * the live project) so every role's screens have something to show during a
 * local visual pass of the app (flutter run --dart-define=USE_FIREBASE_EMULATORS=true).
 *
 * The admin account is NOT created here — run seed-admin.ts for that (it
 * already exists; this script does not duplicate it).
 *
 * Creates (idempotent: fixed ids, so re-running overwrites rather than duplicates):
 *   - customer, vendor and driver Auth users + users/{uid} profiles
 *   - an approved, open vendor with a pickup location and two menu sections
 *   - an approved, available driver
 *   - a default saved address for the customer
 *   - a minimal Damascus location fixture (governorate, city, neighborhoods)
 *   - orders in several statuses (pending, preparing, readyForPickup,
 *     delivering, delivered) so tracking, the driver's available/active
 *     delivery views and the vendor's order lists all have content
 *
 * The passwords below are emulator-only test credentials (same pattern as
 * seed-admin.ts); they grant nothing on the live project.
 *
 * Not part of the deployed Cloud Functions build (outside tsconfig's "src").
 * Run from functions/ while `firebase emulators:start` is running:
 *
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
 *   FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
 *   npx ts-node scripts/seed-local-visual.ts
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "delivery-app-syria-2026";
const LOCAL_HOSTS = new Set(["localhost", "127.0.0.1"]);

/** Refuses to run unless both Admin SDK targets point at a local emulator. */
function assertLocalEmulatorsOnly(): void {
  for (const name of ["FIRESTORE_EMULATOR_HOST", "FIREBASE_AUTH_EMULATOR_HOST"]) {
    const value = process.env[name];
    const host = value ? value.split(":")[0] : "";
    if (!value || !LOCAL_HOSTS.has(host)) {
      throw new Error(
        `Refusing to run: ${name} must be set to localhost:<port> or 127.0.0.1:<port> ` +
          `(got ${value ? `"${value}"` : "nothing"}). This script bypasses firestore.rules ` +
          "via the Admin SDK and must never touch the live project."
      );
    }
  }
  if (process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    throw new Error("Refusing to run with GOOGLE_APPLICATION_CREDENTIALS set — emulators need no credentials.");
  }
}

const PASSWORD = "LocalTest123!";

const ACCOUNTS = {
  customer: { email: "customer@local.test", displayName: "زبون تجريبي", phone: "+963900000101" },
  vendor: { email: "vendor@local.test", displayName: "مطعم تجريبي", phone: "+963900000102" },
  driver: { email: "driver@local.test", displayName: "سائق تجريبي", phone: "+963900000103" },
} as const;

type Role = keyof typeof ACCOUNTS;

// Damascus centre and a nearby pickup point.
const DAMASCUS = { lat: 33.5138, lng: 36.2765 };
const PICKUP = { lat: 33.5102, lng: 36.2913, address: "شارع بغداد، دمشق" };
const DELIVERY = { lat: 33.5225, lng: 36.2805, address: "المزرعة، بناء 12، الطابق 3" };

const NEIGHBORHOODS: Array<[id: string, nameEn: string, nameAr: string]> = [
  ["damascus_al_mazraa", "Al Mazraa", "المزرعة"],
  ["damascus_al_malki", "Al Malki", "المالكي"],
  ["damascus_abu_rummaneh", "Abu Rummaneh", "أبو رمانة"],
  ["damascus_bab_touma", "Bab Touma", "باب توما"],
  ["damascus_al_midan", "Al Midan", "الميدان"],
  ["damascus_kafr_souseh", "Kafr Souseh", "كفرسوسة"],
];

const MENU: Array<{ id: string; name: string; price: number; section: string; description: string; orderCount: number }> = [
  { id: "shawarma-chicken", name: "شاورما دجاج", price: 25000, section: "سندويشات", description: "خبز صاج، ثوم، مخلل", orderCount: 42 },
  { id: "shawarma-meat", name: "شاورما لحمة", price: 32000, section: "سندويشات", description: "طحينة، بندورة، بقدونس", orderCount: 31 },
  { id: "falafel", name: "فلافل", price: 12000, section: "سندويشات", description: "خضار مشكلة وطحينة", orderCount: 18 },
  { id: "meal-family", name: "وجبة عائلية", price: 145000, section: "وجبات", description: "8 سندويشات، بطاطا، مشروبات", orderCount: 9 },
  { id: "meal-crispy", name: "وجبة كريسبي", price: 55000, section: "وجبات", description: "4 قطع، بطاطا، كولسلو", orderCount: 14 },
  { id: "fries", name: "بطاطا مقلية", price: 15000, section: "وجبات", description: "", orderCount: 5 },
];

async function ensureUser(auth: admin.auth.Auth, role: Role): Promise<string> {
  const { email, displayName } = ACCOUNTS[role];
  try {
    const existing = await auth.getUserByEmail(email);
    return existing.uid;
  } catch {
    const created = await auth.createUser({ email, password: PASSWORD, displayName });
    return created.uid;
  }
}

async function main() {
  assertLocalEmulatorsOnly();
  admin.initializeApp({ projectId: PROJECT_ID });
  const auth = admin.auth();
  const db = admin.firestore();
  const now = Date.now();
  const minutes = (n: number) => now - n * 60 * 1000;

  const uid = {
    customer: await ensureUser(auth, "customer"),
    vendor: await ensureUser(auth, "vendor"),
    driver: await ensureUser(auth, "driver"),
  };

  const batch = db.batch();

  // Location fixture (minimal Damascus subset).
  batch.set(db.doc("governorates/damascus"), { nameEn: "Damascus", nameAr: "دمشق", enabled: true, order: 0 });
  batch.set(db.doc("cities/damascus"), {
    nameEn: "Damascus", nameAr: "دمشق", enabled: true, order: 0, governorateId: "damascus",
  });
  NEIGHBORHOODS.forEach(([id, nameEn, nameAr], order) => {
    batch.set(db.doc(`neighborhoods/${id}`), { nameEn, nameAr, cityId: "damascus", enabled: true, order, ochaPcode: null });
  });

  // Profiles.
  for (const role of Object.keys(ACCOUNTS) as Role[]) {
    const { email, displayName, phone } = ACCOUNTS[role];
    batch.set(db.doc(`users/${uid[role]}`), {
      email, displayName, role, phoneNumber: phone, favoriteVendorIds: role === "customer" ? [uid.vendor] : [],
    });
  }

  // Approved, open vendor (doc id == owner uid, as AuthService.signUp does).
  batch.set(db.doc(`vendors/${uid.vendor}`), {
    ownerId: uid.vendor,
    name: ACCOUNTS.vendor.displayName,
    description: "شاورما ووجبات سريعة — بيانات اختبار محلية",
    imageUrl: null,
    logoUrl: null,
    isOpen: true,
    approvalStatus: "approved",
    ratingSum: 27,
    ratingCount: 6,
    category: "restaurants",
    city: "damascus",
    deliveryFee: 10000,
    etaMinMinutes: 25,
    etaMaxMinutes: 40,
    minimumOrderAmount: 20000,
    openTime: "10:00",
    closeTime: "23:59",
    pickupAddress: PICKUP.address,
    pickupLatitude: PICKUP.lat,
    pickupLongitude: PICKUP.lng,
  });
  for (const item of MENU) {
    batch.set(db.doc(`vendors/${uid.vendor}/menuItems/${item.id}`), {
      vendorId: uid.vendor,
      name: item.name,
      price: item.price,
      imageUrl: null,
      available: true,
      description: item.description || null,
      section: item.section,
      orderCount: item.orderCount,
    });
  }

  // Approved, available driver.
  batch.set(db.doc(`drivers/${uid.driver}`), {
    userId: uid.driver,
    isAvailable: true,
    lastKnownLocation: { driverId: uid.driver, latitude: DAMASCUS.lat, longitude: DAMASCUS.lng, heading: null, speed: null, updatedAt: now },
    ratingSum: 14,
    ratingCount: 3,
    approvalStatus: "approved",
  });

  // Customer's default address.
  batch.set(db.doc(`users/${uid.customer}/addresses/home`), {
    userId: uid.customer,
    label: "المنزل",
    latitude: DELIVERY.lat,
    longitude: DELIVERY.lng,
    governorateId: "damascus",
    cityId: "damascus",
    neighborhoodId: "damascus_al_mazraa",
    addressText: DELIVERY.address,
    deliveryInstructions: "الباب الأيسر",
    driverNote: null,
    phone: ACCOUNTS.customer.phone,
    isDefault: true,
    createdAt: minutes(60 * 24),
    updatedAt: minutes(60 * 24),
  });

  // Orders — same shape createOrder writes (functions/src/createOrder.ts).
  const item = (id: string, quantity: number) => {
    const m = MENU.find((x) => x.id === id)!;
    return { menuItemId: m.id, name: m.name, quantity, unitPrice: m.price };
  };
  const order = (
    id: string,
    status: string,
    items: ReturnType<typeof item>[],
    ageMinutes: number,
    driverId: string | null
  ) => {
    const subtotal = items.reduce((sum, i) => sum + i.unitPrice * i.quantity, 0);
    const deliveryFee = 10000;
    batch.set(db.doc(`orders/${id}`), {
      customerId: uid.customer,
      vendorId: uid.vendor,
      vendorOwnerId: uid.vendor,
      driverId,
      items,
      status,
      subtotal,
      deliveryFee,
      total: subtotal + deliveryFee,
      deliveryAddress: DELIVERY.address,
      createdAt: minutes(ageMinutes),
      proofImageUrl: null,
      deliveryLatitude: DELIVERY.lat,
      deliveryLongitude: DELIVERY.lng,
      governorateId: "damascus",
      cityId: "damascus",
      neighborhoodId: "damascus_al_mazraa",
      deliveryInstructions: "الباب الأيسر",
      driverNote: null,
      vendorName: ACCOUNTS.vendor.displayName,
      pickupAddress: PICKUP.address,
      pickupLatitude: PICKUP.lat,
      pickupLongitude: PICKUP.lng,
    });
  };
  order("local-order-pending", "pending", [item("shawarma-chicken", 2), item("fries", 1)], 3, null);
  order("local-order-preparing", "preparing", [item("meal-crispy", 1)], 15, null);
  order("local-order-ready", "readyForPickup", [item("shawarma-meat", 3), item("falafel", 2)], 25, null);
  order("local-order-delivering", "delivering", [item("meal-family", 1)], 40, uid.driver);
  order("local-order-delivered", "delivered", [item("shawarma-chicken", 1), item("falafel", 1)], 60 * 26, uid.driver);

  // The driver's live position on the in-flight delivery (tracking map).
  batch.set(db.doc("orders/local-order-delivering/driverLocation/current"), {
    driverId: uid.driver,
    latitude: (PICKUP.lat + DELIVERY.lat) / 2,
    longitude: (PICKUP.lng + DELIVERY.lng) / 2,
    heading: 0,
    speed: 8,
    updatedAt: now,
  });

  await batch.commit();
  console.log("Seeded local visual data into the emulators:");
  for (const role of Object.keys(ACCOUNTS) as Role[]) console.log(`  ${role}: ${ACCOUNTS[role].email}`);
  console.log("  (admin: run seed-admin.ts — admin@e2e.test)");
  console.log("  password for the three accounts above: see PASSWORD in this script (emulator-only)");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error instanceof Error ? error.message : error);
    process.exit(1);
  });
