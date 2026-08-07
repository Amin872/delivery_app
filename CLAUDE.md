# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A delivery marketplace app with three user roles — **customer**, **driver**, **vendor** — sharing a
single Flutter codebase, backed by Firebase (Auth, Firestore, Cloud Functions, Storage, FCM). This is
a freshly scaffolded project: the data model and screens are minimal skeletons, not a finished product.

## Repository layout

- `mobile/` — Flutter client (all three roles; routed by the signed-in user's `role` field, see below)
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

## First-time setup required before running

The scaffold has no real Firebase project wired in yet:

1. Replace the placeholder project ID in `.firebaserc`.
2. From `mobile/`, run `flutterfire configure` — this generates `lib/firebase_options.dart` (not yet
   present) and the native config files (`google-services.json`, `GoogleService-Info.plist`). Without
   this, `Firebase.initializeApp()` in `lib/main.dart` fails at runtime.
3. `google_maps_flutter` needs a Maps API key added to the Android manifest / iOS `AppDelegate.swift`.

## Architecture

### Role-based routing, one app binary

There's no separate app per role. `lib/routing/app_router.dart` (go_router) redirects unauthenticated
users to `/login`, and once signed in, `_RoleGate` reads the user's Firestore `users/{uid}` document
(via `currentAppUserProvider` in `lib/features/auth/providers/auth_provider.dart`) and dispatches to
`CustomerHomeScreen`, `DriverHomeScreen`, or `VendorDashboardScreen` based on `AppUser.role`. Firebase
Auth tells you *who* is signed in; the Firestore user doc tells you *what role* they have — these are
two separate async steps (`authStateChangesProvider` → `currentAppUserProvider`), both must resolve
before routing a signed-in user anywhere.

### State management: Riverpod providers wrap services, not the reverse

`lib/services/*.dart` (`AuthService`, `FirestoreService`, `LocationService`) are plain Dart classes with
no Riverpod dependency — they take an optional injected instance (e.g. `AuthService({FirebaseAuth? auth})`)
for testability. Riverpod providers (`authServiceProvider`, `firestoreServiceProvider` in
`lib/features/customer/screens/customer_home_screen.dart`) just construct and expose these services;
screens depend on providers, never instantiate services directly. `FirestoreService` streams
(`watchOpenVendors`, `watchVendorOrders`, etc.) are the single place collection names and query shapes
live — don't put raw `FirebaseFirestore.instance.collection(...)` calls in screen/widget code.

### Firestore schema (see also README.md "Data model")

- `users/{uid}` — profile + `role` (`customer` | `driver` | `vendor`); doc ID **is** the Firebase Auth UID
- `vendors/{vendorId}` — storefront, `ownerId` links back to a `users` doc; `menuItems` subcollection
- `drivers/{uid}` — availability + `lastKnownLocation`; doc ID is also the Auth UID
- `orders/{orderId}` — `items[]`, `status` (see `OrderStatus` enum in `lib/models/order.dart`), and
  `customerId` / `vendorId` / `driverId` foreign keys

All four collections' rules in `firestore.rules` key off these same relationships (e.g. an order is
readable by whoever's uid matches `customerId`, `driverId`, or the owner of `vendorId`) — when adding
a field that changes who should read/write a doc, update the rule in the matching `match` block, not
just the Dart model.

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
no-ops if absent. The client side of writing that token (`FirebaseMessaging.instance.getToken()` →
`users/{uid}.fcmToken`) is not yet implemented in `mobile/` — needed before notifications actually
reach a device. Order-lifecycle triggers (`onOrderCreated` notifies the vendor owner, `onOrderStatusChanged`
notifies the customer) live in `functions/src/orders.ts` alongside `acceptDelivery`, since they all
operate on the same `orders/{orderId}` trigger surface.
