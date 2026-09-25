import * as functionsV1 from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";

import { db } from "./admin";
import { isValidDocId } from "./auth";

// Account deletion (Phase 31 M1). The client only deletes the Firebase Auth
// account (AuthService.deleteAccount); firestore.rules forbid deleting
// users/{uid} from any client, so a user can't delete their profile and
// recreate it with another role. Once Auth has actually deleted the
// account, this trigger removes the profile and saved addresses with the
// Admin SDK.
//
// Deliberately NOT touched: orders, reviews, vendors/{uid}, drivers/{uid},
// Storage objects — historical records keep referencing the uid, and every
// reader already tolerates a missing users doc.

/** Largest number of deletes per batch (Firestore's limit is 500). */
const BATCH_SIZE = 400;

/** The Firestore surface this cleanup uses — satisfied by the Admin SDK's
 * Firestore (and the rules-unit-testing compat client), so it can be
 * exercised against the emulator or a fake. */
export interface AccountCleanupStore {
  doc(path: string): {
    delete(): Promise<unknown>;
    collection(id: string): {
      get(): Promise<{ docs: Array<{ ref: unknown }> }>;
    };
  };
  batch(): {
    delete(ref: never): unknown;
    commit(): Promise<unknown>;
  };
}

/**
 * Deletes users/{uid}/addresses/* and then users/{uid}. Safe to run when the
 * profile or the addresses are already gone (deleting a missing doc is a
 * no-op) and safe to retry. Returns how many addresses were removed.
 */
export async function deleteAccountData(store: AccountCleanupStore, uid: string): Promise<{ addressesDeleted: number }> {
  if (!isValidDocId(uid)) {
    throw new Error(`Refusing to clean up an invalid uid: ${JSON.stringify(uid)}`);
  }
  const userRef = store.doc(`users/${uid}`);
  const addresses = (await userRef.collection("addresses").get()).docs;
  for (let start = 0; start < addresses.length; start += BATCH_SIZE) {
    const batch = store.batch();
    for (const address of addresses.slice(start, start + BATCH_SIZE)) {
      batch.delete(address.ref as never);
    }
    await batch.commit();
  }
  await userRef.delete();
  return { addressesDeleted: addresses.length };
}

// Runs as the Compute Engine default service account — the identity every
// deployed gen2 function in this project already uses. 1st gen would
// otherwise default to the App Engine default service account, which this
// project likely doesn't have (no App Engine app; Phase 32 Step 3).
export const onAuthUserDeleted = functionsV1
  .runWith({
    serviceAccount: "637107525940-compute@developer.gserviceaccount.com",
  })
  .auth.user()
  .onDelete(async (user) => {
    const result = await deleteAccountData(db as unknown as AccountCleanupStore, user.uid);
    logger.info("Deleted account profile data", { uid: user.uid, ...result });
  });
