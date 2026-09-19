import { HttpsError } from "firebase-functions/v2/https";

/**
 * Narrow structural shape of the piece of the Admin Firestore SDK
 * `assertIsDriver` needs — lets tests pass a lightweight fake instead of
 * spinning up the Firestore emulator.
 */
export interface UserRoleReader {
  collection(path: string): {
    doc(id: string): {
      get(): Promise<{ data(): { role?: string } | undefined }>;
    };
  };
}

/**
 * Throws `permission-denied` unless `users/{uid}` exists and has
 * `role == 'driver'`. `acceptDelivery` is the only enforcement point for
 * driver assignment (firestore.rules deliberately grants no client-side
 * path to set `driverId`), so without this check any signed-in account —
 * customer or vendor included — could self-assign as the delivery driver.
 */
export async function assertIsDriver(reader: UserRoleReader, uid: string): Promise<void> {
  const userDoc = await reader.collection("users").doc(uid).get();
  const role = userDoc.data()?.role;
  if (role !== "driver") {
    throw new HttpsError("permission-denied", "Only drivers can accept deliveries.");
  }
}

/**
 * Throws `permission-denied` unless `users/{uid}` exists and has
 * `role == 'admin'`. Mirrors `assertIsDriver` above — every admin-only
 * callable (adminCancelOrder, adminReassignDriver, ...) uses this as its
 * sole enforcement point, since firestore.rules deliberately grants admins
 * no client-side write access to orders (see the driver-assignment
 * architecture note in CLAUDE.md); these callables are the only path in.
 */
export async function assertIsAdmin(reader: UserRoleReader, uid: string): Promise<void> {
  const userDoc = await reader.collection("users").doc(uid).get();
  const role = userDoc.data()?.role;
  if (role !== "admin") {
    throw new HttpsError("permission-denied", "Only admins can perform this action.");
  }
}
