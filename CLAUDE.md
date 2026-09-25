# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A delivery marketplace app with four user roles — **customer**, **driver**, **vendor**, **admin** —
sharing a single Flutter codebase, backed by Firebase (Auth, Firestore, Cloud Functions, Storage, FCM).

## Repository layout

- `mobile/` — Flutter client (all four roles; routed by the signed-in user's `role` field, see below)
- `functions/` — Firebase Cloud Functions, TypeScript, compiled with `tsc` to `functions/lib/`
- `firebase.json`, `.firebaserc` — Firebase project wiring (emulator ports, functions predeploy hooks)
- `firestore.rules`, `firestore.indexes.json`, `storage.rules` — Firebase security rules, at repo root
  (not inside `mobile/` or `functions/`) because they govern the whole backend, not one client

## Commands

All Flutter commands run from `mobile/`; all Node/Functions commands run from `functions/`.

```
# Flutter app
cd mobile
flutter pub get                 # install/update dependencies
flutter analyze                 # static analysis — run after any lib/ change
flutter test                    # run all tests in test/
flutter test test/widget_test.dart --plain-name "AppUser round-trips"   # run a single test
flutter run                     # run on a connected device/emulator

# Cloud Functions
cd functions
npm install
npm run build                   # tsc compile, must pass before deploy
npm run lint                    # eslint (flat config, eslint.config.js)
npm test                        # mocha + ts-node, tests matched by src/**/*.spec.ts

# Firebase project (run from repo root)
firebase emulators:start        # Auth :9099, Firestore :8080, Functions :5001, Storage :9199, UI enabled
firebase deploy --only functions
firebase deploy --only firestore:rules,firestore:indexes
firebase deploy --only storage
```

`firebase.json` runs `npm run lint && npm run build` in `functions/` automatically as a predeploy hook
for `firebase deploy --only functions` — a broken build or lint error blocks deploy.

## Firebase project

Wired to `delivery-app-syria-2026` (see `.firebaserc`) — a dedicated project created specifically for
delivery_app (Firestore Native mode, Auth, and Storage all provisioned; no other app shares it).
`flutterfire configure -p delivery-app-syria-2026 -y --platforms=android,ios,web`
has been run, generating `mobile/lib/firebase_options.dart` (wired into `lib/main.dart` via
`DefaultFirebaseOptions.currentPlatform`) and `mobile/android/app/google-services.json`.

`ios/Runner/GoogleService-Info.plist` was **not** generated — FlutterFire CLI only embeds it into the
Xcode project from macOS. Re-run the same `flutterfire configure` command from a Mac before building
for iOS.

The Google Maps SDK key (`google_maps_flutter` tiles: live tracking map, location picker) is
**never committed** — it's injected from untracked local files, with a placeholder fallback so builds
without a key still compile (tiles then stay grey):
- Android: `MAPS_API_KEY=...` in the gitignored `mobile/android/local.properties`, read by
  `android/app/build.gradle.kts` into `manifestPlaceholders`, used as `${MAPS_API_KEY}` by the
  `com.google.android.geo.API_KEY` meta-data in `AndroidManifest.xml`.
- iOS: `MAPS_API_KEY = ...` in the gitignored `mobile/ios/Flutter/Maps.xcconfig` (optionally included by
  `Debug.xcconfig`/`Release.xcconfig`) → `GMSApiKey` in `Info.plist` → read by `AppDelegate.swift`.
Mapbox geocoding (search / reverse geocoding) is a separate token, `--dart-define=MAPBOX_PUBLIC_TOKEN=...`.
See `mobile/README.md` for setup and key restrictions. Driver turn-by-turn navigation is a Google Maps
HTTPS directions link (`lib/core/location/navigation_launcher.dart`) and needs no key.

To repoint this app at a different Firebase project: update `.firebaserc`, then re-run
`flutterfire configure -p <project-id> -y --platforms=android,ios,web` from `mobile/`.

## Architecture

### Role-based routing, one app binary

There's no separate app per role. `lib/routing/app_router.dart` (go_router) redirects unauthenticated
users to `/login`, and once signed in, `_RoleGate` reads the user's Firestore `users/{uid}` document
(via `currentAppUserProvider` in `lib/features/auth/providers/auth_provider.dart`) and dispatches to
`CustomerHomeScreen`, `DriverHomeScreen`, `VendorDashboardScreen`, or `AdminDashboardScreen` based on
`AppUser.role` (`UserRole` enum in `lib/models/app_user.dart`). Firebase Auth tells you *who* is
signed in; the Firestore user doc tells you *what role* they have — these are two separate async steps
(`authStateChangesProvider` → `currentAppUserProvider`), both must resolve before routing a signed-in
user anywhere.

### State management: Riverpod providers wrap services, not the reverse

`lib/services/*.dart` (`AuthService`, `FirestoreService`, `LocationService`) are plain Dart classes with
no Riverpod dependency — they take an optional injected instance (e.g. `AuthService({FirebaseAuth? auth})`)
for testability. Riverpod providers just construct and expose these services — `authServiceProvider` in
`lib/features/auth/providers/auth_provider.dart`, `firestoreServiceProvider` in
`lib/features/customer/screens/customer_home_screen.dart` — screens depend on providers, never
instantiate services directly. `FirestoreService` streams
(`watchOpenVendors`, `watchVendorOrders`, etc.) are the single place collection names and query shapes
live — don't put raw `FirebaseFirestore.instance.collection(...)` calls in screen/widget code.

### Firestore schema (see also README.md "Data model")

- `users/{uid}` — profile + `role` (`customer` | `driver` | `vendor` | `admin`); doc ID **is** the
  Firebase Auth UID
- `vendors/{vendorId}` — storefront, `ownerId` links back to a `users` doc; `approvalStatus`
  (`pending` | `approved` | `rejected`, see `VendorApprovalStatus` in `lib/models/vendor.dart`);
  `ratingSum` / `ratingCount` (aggregated from `reviews`, see below); `menuItems` subcollection
- `drivers/{uid}` — availability + `lastKnownLocation` + `ratingSum` / `ratingCount`; doc ID is also
  the Auth UID
- `orders/{orderId}` — `items[]`, `status` (see `OrderStatus` enum in `lib/models/order.dart`), and
  `customerId` / `vendorId` / `driverId` foreign keys
- `reviews/{orderId}` — one customer review per delivered order (doc ID **is** the order ID, not
  auto-generated); `vendorRating` / `driverRating` (1-5) + optional `comment`, see `lib/models/review.dart`

All five collections' rules in `firestore.rules` key off these same relationships (e.g. an order is
readable by whoever's uid matches `customerId`, `driverId`, or the owner of `vendorId`) — when adding
a field that changes who should read/write a doc, update the rule in the matching `match` block, not
just the Dart model.

### Vendor approval is a client write gated by rules, not a callable

New vendors are created with `approvalStatus: 'pending'` (`AuthService.signUp`); `firestore.rules`'
`vendors/{vendorId}` `allow update` only lets an owner touch their own doc while leaving `ownerId` and
`approvalStatus` unchanged. A caller with `hasRole('admin')` may change only a fixed whitelist of
fields — `approvalStatus`, `category`, `city`, `deliveryFee`, `etaMinMinutes`, `etaMaxMinutes`,
`minimumOrderAmount`, `openTime`, `closeTime`, `isOpen`
(`request.resource.data.diff(resource.data).affectedKeys().hasOnly([...])`) — covering approval, the
store's operating terms and open/closed; name, description, logo, pickup location, `ownerId` and the
rating aggregates stay out of the admin's reach. Unlike
driver assignment below, this is a plain client write straight from `FirestoreService` — there's no
race to arbitrate, so no callable is needed.

### Driver assignment is a transaction in Cloud Functions, not a client write

Two drivers could race to accept the same `readyForPickup` order. `functions/src/orders.ts`'s
`acceptDelivery` callable runs a Firestore transaction that checks `status == 'readyForPickup' &&
!driverId` before assigning, so only one caller wins. Because of this, `firestore.rules` deliberately
has **no** client-side rule permitting a driver to set `driverId`/`status` directly — that path only
exists through the Admin-SDK-authenticated callable. If you add other driver-initiated state changes,
default to a callable function with a transaction rather than a permissive client rule, for the same
race-condition reason.

### Push notifications: FCM token on the user doc, not a separate collection

`functions/src/notifications.ts` is the single push module: `orderNotifications(before, after, orderId,
vendorOwnerId)` is a pure planner deciding who gets which template for an order write (vendor on
creation; customer on every status step; vendor on driverAssigned/delivered; customer + vendor +
assigned driver on cancellation; new/previous driver on reassignment, even when the status doesn't
change), and `notifyUser(intent)` is the one sender. It reads `fcmToken` and `locale` off
`users/{uid}`, sends bilingual (ar/en, default ar) text plus a data payload `{type, orderId}`, no-ops
without a token, and clears a token FCM reports as unregistered. Both triggers (`onOrderCreated`,
`onOrderStatusChanged` in `functions/src/orders.ts`) just call the planner and the sender. The client
side lives in `mobile/lib/services/push_notification_service.dart` and
`lib/features/notifications/providers/push_notification_provider.dart`:
`pushNotificationSyncProvider` (re-runs on every auth-state change) registers the single
`users/{uid}.fcmToken` and keeps `users/{uid}.locale` in sync with the app language;
`pushNotificationTapProvider` turns a tapped notification (launch or background) into a pending
target that `NotificationTapHandler` (wrapping each role home in `_RoleGate`) opens with the
existing order screen for the signed-in role. The token is cleared on sign-out in `AuthService.signOut`.
There is no notification inbox/history collection and no preferences yet.

### Ratings: a client-written review, aggregated by a trigger, never a client-written average

A customer rates one delivered order via `FirestoreService.submitReview`, which writes straight to
`reviews/{orderId}` (see `RateOrderDialog` in `lib/features/customer/widgets/`) — the doc ID *is* the
order ID rather than auto-generated, so `firestore.rules`' create-only-if-absent semantics enforce
"one review per order" without a query or a callable. The `reviews/{orderId}` create rule cross-checks
`vendorId`/`driverId`/`customerId` and `status == 'delivered'` against the referenced `orders/{orderId}`
doc, so a review can't be forged for an order that isn't the caller's or isn't finished yet. From there,
`functions/src/reviews.ts`'s `onReviewCreated` trigger is what actually updates `vendors/{vendorId}.ratingSum`
/`ratingCount` and `drivers/{driverId}.ratingSum`/`ratingCount`, via `FieldValue.increment` — no
transaction needed (increments commute, and a review can only be created once). `firestore.rules`
deliberately blocks a vendor or driver from touching their own `ratingSum`/`ratingCount` when updating
the rest of their own doc, mirroring the "no client-side write for anything that must stay consistent"
reasoning in the driver-assignment note above — those two fields are Admin-SDK-only in practice, even
though the rest of `vendors`/`drivers` is a plain client write.
