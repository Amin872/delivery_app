/**
 * One-off script: Locations Phase 3 — seeds the 14 Syrian governorates into
 * `governorates/{governorateId}`, and backfills `governorateId` onto the
 * five existing `cities/{cityId}` docs seeded by seed-cities.ts (Phase 1).
 * See the Locations/City migration plan and the Governorates + Syrian
 * Cities Data Foundation Audit for why: this is purely additive — no
 * existing city id, city field, or Vendor.city value changes.
 *
 * Writes via the Admin SDK, bypassing firestore.rules — both `governorates`
 * and `cities` writes are admin-only (see firestore.rules), and this script
 * has no signed-in user context.
 *
 * Every governorate doc id is deterministic and written with `.set()`, so
 * re-running this script is a safe, idempotent overwrite — same reasoning
 * as seed-cities.ts. The five city backfills use `.update()` rather than
 * `.set()`, since those docs already exist (from Phase 1) and must keep
 * their existing nameEn/nameAr/enabled/order untouched — only governorateId
 * is added/overwritten.
 *
 * City → governorate mapping: each of the five existing cities IS its
 * governorate's capital, and (deliberately) shares the same canonical id —
 * damascus→damascus, aleppo→aleppo, homs→homs, latakia→latakia,
 * tartus→tartus — so the backfill below is a direct, unambiguous 1:1 pass,
 * not a guessed mapping.
 *
 * Unlike seed-cities.ts, this script does NOT refuse to run against a
 * Firestore emulator (FIRESTORE_EMULATOR_HOST) — it's designed to be safely
 * testable end-to-end against the emulator before ever touching the live
 * project, since that's the only way to verify the actual writes succeed.
 * The Admin SDK automatically redirects to the emulator when
 * FIRESTORE_EMULATOR_HOST is set; when it's unset, this runs against the
 * real delivery-app-syria-2026 project, gated by --yes same as seed-cities.ts.
 *
 * Usage (real project):
 *   GOOGLE_APPLICATION_CREDENTIALS="$env:APPDATA\firebase\<you>_application_default_credentials.json" \
 *   npx ts-node scripts/seed-governorates.ts --yes
 *
 * Usage (emulator, for testing only):
 *   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 npx ts-node scripts/seed-governorates.ts --yes
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "delivery-app-syria-2026";

interface GovernorateSeed {
  id: string;
  nameEn: string;
  nameAr: string;
  order: number;
}

// Canonical ids and order as approved — the 14 Syrian governorates.
const GOVERNORATES: GovernorateSeed[] = [
  { id: "damascus", nameEn: "Damascus", nameAr: "دمشق", order: 0 },
  { id: "rif_dimashq", nameEn: "Rif Dimashq", nameAr: "ريف دمشق", order: 1 },
  { id: "aleppo", nameEn: "Aleppo", nameAr: "حلب", order: 2 },
  { id: "homs", nameEn: "Homs", nameAr: "حمص", order: 3 },
  { id: "hama", nameEn: "Hama", nameAr: "حماة", order: 4 },
  { id: "latakia", nameEn: "Latakia", nameAr: "اللاذقية", order: 5 },
  { id: "tartus", nameEn: "Tartus", nameAr: "طرطوس", order: 6 },
  { id: "idlib", nameEn: "Idlib", nameAr: "إدلب", order: 7 },
  { id: "raqqa", nameEn: "Raqqa", nameAr: "الرقة", order: 8 },
  { id: "deir_ezzor", nameEn: "Deir ez-Zor", nameAr: "دير الزور", order: 9 },
  { id: "hasakah", nameEn: "Al-Hasakah", nameAr: "الحسكة", order: 10 },
  { id: "daraa", nameEn: "Daraa", nameAr: "درعا", order: 11 },
  { id: "quneitra", nameEn: "Quneitra", nameAr: "القنيطرة", order: 12 },
  { id: "suwayda", nameEn: "As-Suwayda", nameAr: "السويداء", order: 13 },
];

// Each of the five existing cities shares its governorate's canonical id.
const CITY_GOVERNORATE_IDS = ["damascus", "aleppo", "homs", "latakia", "tartus"];

async function main() {
  if (!process.argv.includes("--yes")) {
    throw new Error(
      "Refusing to run without --yes — this writes to the LIVE delivery-app-syria-2026 project " +
        "unless FIRESTORE_EMULATOR_HOST is set."
    );
  }

  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();

  for (const governorate of GOVERNORATES) {
    await db.collection("governorates").doc(governorate.id).set({
      nameEn: governorate.nameEn,
      nameAr: governorate.nameAr,
      enabled: true,
      order: governorate.order,
    });
    console.log(`Seeded governorates/${governorate.id}`);
  }

  for (const cityId of CITY_GOVERNORATE_IDS) {
    await db.collection("cities").doc(cityId).update({ governorateId: cityId });
    console.log(`Backfilled cities/${cityId}.governorateId = ${cityId}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
