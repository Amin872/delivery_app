/**
 * One-off script: seeds 10 demo grocery-store vendors, each with 10 diverse
 * grocery/produce menu items, directly into the LIVE delivery-app-syria-2026
 * Firestore project — unlike seed-admin.ts (emulator-only), this is meant to
 * give the already-running app (pointed at the live project, see CLAUDE.md)
 * something to show instead of an empty vendor list.
 *
 * Writes via the Admin SDK, bypassing firestore.rules — a plain client
 * write can't set approvalStatus: 'approved' directly (see the
 * vendors/{vendorId} rule in firestore.rules and the "Vendor approval" note
 * in CLAUDE.md), and vendors need isOpen: true + approvalStatus: 'approved'
 * to appear in FirestoreService.watchOpenVendors().
 *
 * Every doc is deterministically IDed (seed-vendor-01..10 / item-01..10)
 * and tagged `seedTag: DEMO_SEED_TAG`, so re-running this script is a no-op
 * overwrite rather than a duplicate, and cleanup-demo-vendors.ts can remove
 * exactly this data later without touching anything real.
 *
 * Credentials: uses Application Default Credentials, pointed at the
 * `firebase login`'d account's own cached credentials file rather than a
 * separate service account key:
 *
 *   GOOGLE_APPLICATION_CREDENTIALS="$env:APPDATA\firebase\<you>_application_default_credentials.json" \
 *   npx ts-node scripts/seed-demo-vendors.ts --yes
 *
 * Refuses to run without --yes (copy-paste guard, since this writes to the
 * live project) or against an emulator env (use seed-admin.ts's pattern
 * instead if that's actually what you want).
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "delivery-app-syria-2026";
export const DEMO_SEED_TAG = "demo-seed-v1";

interface DemoProduct {
  name: string;
  price: number;
  // Vendor-authored menu grouping (MenuItem.section, a free-text field —
  // see the "category" note in vendor_menu_screen's Phase 4B changes).
  // Arabic since that's this app's primary customer language; deliberately
  // grocery-specific rather than the restaurant categories (شاورما، برغر...)
  // mentioned in the phase brief, because these 10 demo vendors are all
  // `category: "groceries"` below — the section names should match what
  // they're actually selling.
  section: string;
  // Baseline popularity used to derive a per-vendor MenuItem.orderCount
  // below (see orderCountForVendor) — demo-only, so buildMenuSections' real
  // "most ordered" ranking (core/discovery/menu_sections.dart) has
  // non-zero, non-uniform data to actually rank instead of every item
  // tying at 0 and the section never appearing.
  baseOrderCount: number;
}

// Deliberately spans fruit, vegetable, dairy, protein, bakery, pantry and
// beverage so each vendor's 10 items read as a real grocery aisle, not a
// repeated single category.
const DEMO_PRODUCTS: DemoProduct[] = [
  { name: "Fresh Bananas (1kg)", price: 1.99, section: "الفواكه", baseOrderCount: 42 },
  { name: "Organic Avocados (4-pack)", price: 2.49, section: "الفواكه", baseOrderCount: 27 },
  { name: "Baby Spinach (200g)", price: 2.99, section: "الخضار", baseOrderCount: 18 },
  { name: "Roma Tomatoes (1kg)", price: 1.79, section: "الخضار", baseOrderCount: 33 },
  { name: "Whole Milk (1L)", price: 1.49, section: "الألبان والبيض", baseOrderCount: 38 },
  { name: "Free-Range Eggs (12-pack)", price: 3.99, section: "الألبان والبيض", baseOrderCount: 45 },
  { name: "Sourdough Bread Loaf", price: 4.5, section: "المخبوزات", baseOrderCount: 30 },
  { name: "Chicken Breast (1kg)", price: 7.99, section: "اللحوم", baseOrderCount: 25 },
  { name: "Basmati Rice (2kg)", price: 5.99, section: "المواد الغذائية", baseOrderCount: 12 },
  { name: "Orange Juice (1L)", price: 3.29, section: "المشروبات", baseOrderCount: 20 },
];

const DEMO_VENDORS = [
  { name: "Green Valley Grocers", description: "Neighborhood grocer with fresh produce daily." },
  { name: "Sunrise Farmers Market", description: "Locally sourced fruits and vegetables." },
  { name: "Harvest Basket", description: "Farm-to-table grocery essentials." },
  { name: "City Fresh Mart", description: "Your everyday grocery stop in the city center." },
  { name: "Golden Fields Grocery", description: "Quality staples at fair prices." },
  { name: "Blue Ridge Produce Co.", description: "Hand-picked produce and pantry goods." },
  { name: "Nile Fresh Market", description: "Fresh groceries, delivered fast." },
  { name: "Cedar Grove Grocers", description: "A family-run grocery since day one." },
  { name: "Oasis Organic Market", description: "Organic and sustainably sourced groceries." },
  { name: "Riverside Grocery", description: "Riverside's favorite spot for fresh groceries." },
];

function priceForVendor(base: number, vendorIndex: number): number {
  // Small deterministic per-vendor variation so prices aren't identical
  // across all 10 stores — cosmetic only, keeps the demo data believable.
  const variation = 1 + ((vendorIndex % 5) - 2) * 0.03;
  return Math.round(base * variation * 100) / 100;
}

// Rotates which products are "hot" per vendor (deterministically — no
// Math.random, so re-running this script still produces the exact same
// data per the file's own idempotency guarantee above) so all 10 demo
// stores don't render an identical "Most ordered" carousel in the same
// order, while every number stays a plausible order count.
function orderCountForVendor(productIndex: number, vendorIndex: number): number {
  const rotated = DEMO_PRODUCTS[(productIndex + vendorIndex) % DEMO_PRODUCTS.length];
  return rotated.baseOrderCount;
}

async function main() {
  if (!process.argv.includes("--yes")) {
    throw new Error(
      "Refusing to run without --yes — this script writes real documents to the LIVE " +
        `${PROJECT_ID} Firestore project. Re-run with --yes once you're sure.`
    );
  }
  if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST is set — unset it first. " +
        "This script is for the live project only; use seed-admin.ts's pattern for the emulator."
    );
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: PROJECT_ID,
  });
  const db = admin.firestore();

  for (let i = 0; i < DEMO_VENDORS.length; i++) {
    const vendorId = `seed-vendor-${String(i + 1).padStart(2, "0")}`;
    const vendor = DEMO_VENDORS[i];
    const ratingCount = 8 + i * 3;
    const avgRating = 3.8 + (i % 5) * 0.25; // spread between 3.8 and 4.8
    // Every 3rd store is free delivery, matching the customer app's
    // "Free delivery" badge (see VendorCard) instead of always a flat fee.
    const deliveryFee = i % 3 === 0 ? 0 : 500 + i * 250;
    const etaMinMinutes = 15 + i * 2;
    const etaMaxMinutes = etaMinMinutes + 10;

    await db.collection("vendors").doc(vendorId).set({
      ownerId: `seed-owner-${vendorId}`,
      name: vendor.name,
      description: vendor.description,
      // Wide hero/cover photo — NOT the logo. Kept as a random Picsum photo
      // since it's meant to look like a generic storefront photo.
      imageUrl: `https://picsum.photos/seed/${vendorId}/640/360`,
      // Square logo mark, shown separately in the white logo card (see
      // Vendor.logoUrl / _VendorLogo). Only the first demo vendor
      // ("Green Valley Grocers") gets a real logo image, bundled with the
      // app at mobile/assets/images/logo_reference.png and referenced here
      // by its asset path rather than an https:// URL — _VendorLogo detects
      // this convention and renders it via Image.asset instead of a network
      // fetch. Every other demo vendor deliberately has no logo yet
      // (null), rendering the neutral placeholder icon, to show what a
      // vendor that hasn't uploaded a logo looks like.
      logoUrl: i === 0 ? "assets/images/logo_reference.png" : null,
      isOpen: true,
      category: "groceries",
      city: "damascus",
      deliveryFee,
      etaMinMinutes,
      etaMaxMinutes,
      approvalStatus: "approved",
      ratingSum: Math.round(avgRating * ratingCount),
      ratingCount,
      seedTag: DEMO_SEED_TAG,
    });

    const batch = db.batch();
    DEMO_PRODUCTS.forEach((product, j) => {
      const itemId = `item-${String(j + 1).padStart(2, "0")}`;
      const ref = db.collection("vendors").doc(vendorId).collection("menuItems").doc(itemId);
      batch.set(ref, {
        vendorId,
        name: product.name,
        price: priceForVendor(product.price, i),
        imageUrl: `https://picsum.photos/seed/${vendorId}-${itemId}/400/300`,
        available: true,
        section: product.section,
        orderCount: orderCountForVendor(j, i),
        seedTag: DEMO_SEED_TAG,
      });
    });
    await batch.commit();

    console.log(`Seeded ${vendorId}: ${vendor.name} (${DEMO_PRODUCTS.length} items)`);
  }

  console.log(`\nDone. Seeded ${DEMO_VENDORS.length} vendors x ${DEMO_PRODUCTS.length} items each.`);
  console.log("Run cleanup-demo-vendors.ts with --yes to remove this data later.");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
