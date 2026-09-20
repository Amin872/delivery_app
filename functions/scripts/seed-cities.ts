/**
 * One-off script: seeds the five existing delivery cities — matching
 * mobile/lib/models/city.dart's `City` enum values exactly — into
 * `cities/{cityId}` on the LIVE orient-food-9c1e0 Firestore project. See
 * the Locations/City migration plan for why: `Vendor.city` is already
 * stored as one of these five lowercase strings, so seeding `cities` with
 * these exact same document ids means no existing vendor document needs
 * any backfill at all.
 *
 * Writes via the Admin SDK, bypassing firestore.rules — `cities` write is
 * admin-only (see firestore.rules), and this script has no signed-in user
 * context.
 *
 * Every doc id is deterministic and every write uses `.set()`, so
 * re-running this script is a safe, idempotent overwrite rather than a
 * duplicate — same reasoning as seed-demo-vendors.ts.
 *
 * nameEn/nameAr values and ordering are taken directly from the app's own
 * existing localization strings and `City.values` declaration order
 * (cityDamascus..cityTartus in mobile/lib/l10n/app_en.arb / app_ar.arb) —
 * no new city, spelling, or translation is introduced here.
 *
 * Credentials: uses Application Default Credentials, pointed at the
 * `firebase login`'d account's own cached credentials file rather than a
 * separate service account key:
 *
 *   GOOGLE_APPLICATION_CREDENTIALS="$env:APPDATA\firebase\<you>_application_default_credentials.json" \
 *   npx ts-node scripts/seed-cities.ts --yes
 *
 * Refuses to run without --yes (copy-paste guard, since this writes to the
 * live project) or against an emulator env (this seeds real reference
 * data the live app depends on, not disposable demo/test data).
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "orient-food-9c1e0";

interface CitySeed {
  id: string;
  nameEn: string;
  nameAr: string;
  order: number;
}

// Matches mobile/lib/models/city.dart's `City` enum values exactly (used
// as document ids), mobile/lib/l10n/app_en.arb / app_ar.arb's
// cityDamascus..cityTartus strings exactly (used as nameEn/nameAr), and
// City.values' declared order (used as `order`).
const CITIES: CitySeed[] = [
  { id: "damascus", nameEn: "Damascus", nameAr: "دمشق", order: 0 },
  { id: "aleppo", nameEn: "Aleppo", nameAr: "حلب", order: 1 },
  { id: "homs", nameEn: "Homs", nameAr: "حمص", order: 2 },
  { id: "latakia", nameEn: "Latakia", nameAr: "اللاذقية", order: 3 },
  { id: "tartus", nameEn: "Tartus", nameAr: "طرطوس", order: 4 },
];

async function main() {
  if (!process.argv.includes("--yes")) {
    throw new Error(
      "Refusing to run without --yes — this writes to the LIVE orient-food-9c1e0 project."
    );
  }
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    throw new Error(
      "FIRESTORE_EMULATOR_HOST is set — this script seeds real reference data on the live " +
        "project, not emulator/demo data. Unset it before running."
    );
  }

  admin.initializeApp({ projectId: PROJECT_ID });
  const db = admin.firestore();

  for (const city of CITIES) {
    await db.collection("cities").doc(city.id).set({
      nameEn: city.nameEn,
      nameAr: city.nameAr,
      enabled: true,
      order: city.order,
    });
    console.log(`Seeded cities/${city.id}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
