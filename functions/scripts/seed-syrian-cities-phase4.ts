/**
 * One-off script: Phase 4 Location & Address Architecture — seeds the
 * remaining Syrian governorate-capital cities that seed-cities.ts (Phase 1,
 * the original five: damascus/aleppo/homs/latakia/tartus only) never
 * covered, plus one special-case locality: `damascus_yarmuk` — see the
 * Phase 2/3 data-acquisition reports and models/neighborhood.dart's own
 * "Special Case A" writeup. OCHA's own P-code hierarchy treats "Yarmuk" as
 * a distinct adm4 locality, structurally parallel to (not nested inside)
 * Damascus city itself, both children of the same Damascus district/
 * governorate — seeded here as its own `cities/{id}` doc for the same
 * reason: an independent grouping, not merged into Damascus's own 97
 * neighbourhoods.
 *
 * These seven governorate-capital ids and spellings match
 * seed-governorates.ts exactly (nameEn/nameAr, and cityId ==
 * governorateId, same "the city IS its governorate's capital and shares
 * its canonical id" pattern seed-governorates.ts's own doc comment
 * establishes for the original five) — verified directly against each
 * neighbourhood record's own adm1_en/adm1_pcode field during Phase 3
 * validation (see Phase 3's Section 5, "CITY MAPPINGS TO ADD"), not
 * guessed.
 *
 * Required before functions/scripts/seed-neighborhoods.ts can run:
 * firestore.rules' neighborhoods/{neighborhoodId} create/update rule
 * requires the referenced cities/{cityId} doc to already exist.
 *
 * Writes via the Admin SDK, bypassing firestore.rules — same as
 * seed-cities.ts/seed-governorates.ts. Every doc id is deterministic and
 * written with `.set()`, so re-running this script is a safe, idempotent
 * overwrite.
 *
 * Usage (real project):
 *   GOOGLE_APPLICATION_CREDENTIALS="$env:APPDATA\firebase\<you>_application_default_credentials.json" \
 *   npx ts-node scripts/seed-syrian-cities-phase4.ts --yes
 *
 * Refuses to run without --yes or against an emulator env — same guards as
 * seed-cities.ts/seed-governorates.ts, for the same reasons.
 */
import * as admin from "firebase-admin";

const PROJECT_ID = "delivery-app-syria-2026";

interface CitySeed {
  id: string;
  nameEn: string;
  nameAr: string;
  governorateId: string;
  order: number;
}

const CITIES: CitySeed[] = [
  { id: "raqqa", nameEn: "Raqqa", nameAr: "الرقة", governorateId: "raqqa", order: 5 },
  { id: "hama", nameEn: "Hama", nameAr: "حماة", governorateId: "hama", order: 6 },
  { id: "deir_ezzor", nameEn: "Deir ez-Zor", nameAr: "دير الزور", governorateId: "deir_ezzor", order: 7 },
  { id: "hasakah", nameEn: "Al-Hasakah", nameAr: "الحسكة", governorateId: "hasakah", order: 8 },
  { id: "daraa", nameEn: "Daraa", nameAr: "درعا", governorateId: "daraa", order: 9 },
  { id: "idlib", nameEn: "Idlib", nameAr: "إدلب", governorateId: "idlib", order: 10 },
  { id: "suwayda", nameEn: "As-Suwayda", nameAr: "السويداء", governorateId: "suwayda", order: 11 },
  // Special case — see this file's own doc comment above.
  { id: "damascus_yarmuk", nameEn: "Yarmouk", nameAr: "اليرموك", governorateId: "damascus", order: 12 },
];

async function main() {
  if (!process.argv.includes("--yes")) {
    throw new Error(
      "Refusing to run without --yes — this writes to the LIVE delivery-app-syria-2026 project."
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

  for (const [index, city] of CITIES.entries()) {
    await db.collection("cities").doc(city.id).set({
      nameEn: city.nameEn,
      nameAr: city.nameAr,
      enabled: true,
      order: city.order,
      governorateId: city.governorateId,
    });
    console.log(`Seeded cities/${city.id} (${index + 1}/${CITIES.length})`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
