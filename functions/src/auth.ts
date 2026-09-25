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
 * `role == 'driver'`. Role-only check; acceptDelivery now uses the stricter
 * [assertIsApprovedDriver] below (role AND admin approval), since
 * acceptDelivery is the only client path to set `driverId`
 * (firestore.rules grants none).
 */
export async function assertIsDriver(reader: UserRoleReader, uid: string): Promise<void> {
  const userDoc = await reader.collection("users").doc(uid).get();
  const role = userDoc.data()?.role;
  if (role !== "driver") {
    throw new HttpsError("permission-denied", "Only drivers can accept deliveries.");
  }
}

/**
 * True only when a drivers/{uid} document explicitly says 'approved' — a
 * missing doc, a missing field, or any other value (pending, rejected,
 * unrecognized) is not approved. Shared by acceptDelivery's caller check
 * and adminReassignDriver's target check.
 */
export function isApprovedDriverDoc(driver: { approvalStatus?: unknown } | undefined): boolean {
  return driver?.approvalStatus === "approved";
}

/**
 * Narrow structural shape of the piece of the Admin Firestore SDK
 * `assertIsApprovedDriver` needs — like [UserRoleReader], but reading two
 * collections (users and drivers).
 */
export interface DocReader {
  collection(path: string): {
    doc(id: string): {
      get(): Promise<{ data(): Record<string, unknown> | undefined }>;
    };
  };
}

/**
 * Throws `permission-denied` unless the caller is a driver (users/{uid}
 * role == 'driver') whose account an admin has approved (drivers/{uid}
 * approvalStatus == 'approved'). Used where a driver takes on NEW work
 * (acceptDelivery). Deliberately not used by advanceDelivery, so a driver
 * whose approval is revoked mid-delivery can still finish the order they
 * already hold. Resolves with the drivers/{uid} data it already read, so a
 * caller can make further checks on it (e.g. availability) without a
 * second read.
 */
export async function assertIsApprovedDriver(
  reader: DocReader,
  uid: string
): Promise<Record<string, unknown>> {
  const [userDoc, driverDoc] = await Promise.all([
    reader.collection("users").doc(uid).get(),
    reader.collection("drivers").doc(uid).get(),
  ]);
  if (userDoc.data()?.role !== "driver") {
    throw new HttpsError("permission-denied", "Only drivers can accept deliveries.");
  }
  const driver = driverDoc.data();
  if (!driver || !isApprovedDriverDoc(driver)) {
    throw new HttpsError("permission-denied", "Your driver account is not approved yet.");
  }
  return driver;
}

/**
 * Throws `failed-precondition` (details.reason `driver-unavailable`) unless
 * the driver has switched themselves available (drivers/{uid}.isAvailable
 * === true; missing or any other value counts as offline). Used only where
 * a driver takes on NEW work (acceptDelivery) — never by advanceDelivery, so
 * a driver who goes offline mid-delivery can still finish it.
 */
export function assertDriverAvailable(driver: { isAvailable?: unknown } | undefined): void {
  if (driver?.isAvailable !== true) {
    throw new HttpsError("failed-precondition", "You're offline. Go available to accept deliveries.", {
      reason: "driver-unavailable",
    });
  }
}

/**
 * Throws `permission-denied` unless `users/{uid}` exists and has
 * `role == 'customer'`. `createOrder` is the only path that creates an
 * order (firestore.rules denies every client-side create), so this is what
 * keeps drivers, vendors and admins from placing orders as customers.
 */
export async function assertIsCustomer(reader: UserRoleReader, uid: string): Promise<void> {
  const userDoc = await reader.collection("users").doc(uid).get();
  const role = userDoc.data()?.role;
  if (role !== "customer") {
    throw new HttpsError("permission-denied", "Only customers can place orders.");
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

/** Longest document ID a callable accepts. Auto-generated IDs are 20
 * characters and Auth UIDs 28, so this leaves ample room. */
export const MAX_DOC_ID_LENGTH = 128;

/**
 * Whether [value] is safe to pass to `collection(...).doc(value)` as ONE
 * document ID. The Admin SDK treats "/" in `doc()` as a path separator, so
 * an ID like "O/driverLocation/X" would address `orders/O/driverLocation/X`
 * — a different, client-writable document — instead of `orders/{id}`.
 * Rejected: non-strings, empty/blank, anything over [MAX_DOC_ID_LENGTH],
 * "/" or "\" (path separators), "." and ".." (traversal-style, and not
 * valid Firestore IDs), Firestore-reserved `__…__` IDs, and control
 * characters.
 */
export function isValidDocId(value: unknown): value is string {
  if (typeof value !== "string") return false;
  if (value.trim().length === 0 || value.length > MAX_DOC_ID_LENGTH) return false;
  if (value.includes("/") || value.includes("\\")) return false;
  if (value === "." || value === "..") return false;
  if (/^__.*__$/.test(value)) return false;
  if (/[\u0000-\u001f\u007f]/.test(value)) return false;
  return true;
}

/**
 * [value] as a document ID, or the callable's usual `invalid-argument`
 * error naming [field] — a controlled error instead of a Firestore path
 * error (or a lookup of the wrong document).
 */
export function requireDocId(value: unknown, field: string): string {
  if (!isValidDocId(value)) {
    throw new HttpsError("invalid-argument", `${field} must be a valid document ID.`);
  }
  return value;
}
