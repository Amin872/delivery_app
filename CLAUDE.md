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

Wired to `orient-food-9c1e0` (see `.firebaserc`) — an existing, already-active project (Firestore
Native mode, Auth, and Storage all provisioned; it also has pre-existing `orient_food` Android/web apps
and users unrelated to this codebase). `flutterfire configure -p orient-food-9c1e0 -y --platforms=android,ios,web`
has been run, generating `mobile/lib/firebase_options.dart` (wired into `lib/main.dart` via
`DefaultFirebaseOptions.currentPlatform`) and `mobile/android/app/google-services.json`.

`ios/Runner/GoogleService-Info.plist` was **not** generated — FlutterFire CLI only embeds it into the
Xcode project from macOS. Re-run the same `flutterfire configure` command from a Mac before building
for iOS. The Maps API key wiring for `google_maps_flutter` (live delivery tracking) is in place —
`android/app/src/main/AndroidManifest.xml`'s `com.google.android.geo.API_KEY` meta-data and
`ios/Runner/AppDelegate.swift`'s `GMSServices.provideAPIKey(...)` call — but both still hold the
placeholder `"YOUR_MAPS_API_KEY_HERE"`; swap in a real Maps SDK key from the Google Cloud Console
(same project as `orient-food-9c1e0`, or any project with Maps SDK for Android/iOS enabled) before
`GoogleMap` widgets will render actual tiles instead of a blank grey view.

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
  `menuItems` subcollection
- `drivers/{uid}` — availability + `lastKnownLocation`; doc ID is also the Auth UID
- `orders/{orderId}` — `items[]`, `status` (see `OrderStatus` enum in `lib/models/order.dart`), and
  `customerId` / `vendorId` / `driverId` foreign keys

All four collections' rules in `firestore.rules` key off these same relationships (e.g. an order is
readable by whoever's uid matches `customerId`, `driverId`, or the owner of `vendorId`) — when adding
a field that changes who should read/write a doc, update the rule in the matching `match` block, not
just the Dart model.

### Vendor approval is a client write gated by rules, not a callable

New vendors are created with `approvalStatus: 'pending'` (`AuthService.signUp`); `firestore.rules`'
`vendors/{vendorId}` `allow update` only lets an owner touch their own doc while leaving `ownerId` and
`approvalStatus` unchanged, and only lets a caller with `hasRole('admin')` change `approvalStatus`
alone (`request.resource.data.diff(resource.data).affectedKeys().hasOnly(['approvalStatus'])`). Unlike
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

`functions/src/notifications.ts`'s `notifyUser(userId, ...)` reads `fcmToken` off `users/{userId}` and
no-ops if absent. The client side lives in `mobile/lib/services/push_notification_service.dart`
(`registerToken` requests permission and writes the token, `onTokenRefresh` keeps it current) and is
wired up as a side-effect Riverpod provider, `pushNotificationSyncProvider` in
`lib/features/notifications/providers/push_notification_provider.dart`, which re-runs on every
auth-state change so it covers both a fresh sign-in and an app restart with an existing session; the
token is cleared on sign-out in `AuthService.signOut`. Order-lifecycle triggers (`onOrderCreated`
notifies the vendor owner, `onOrderStatusChanged` notifies the customer) live in
`functions/src/orders.ts` alongside `acceptDelivery`, since they all operate on the same
`orders/{orderId}` trigger surface.
