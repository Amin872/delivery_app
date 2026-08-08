# Delivery App

A delivery marketplace app with four roles — customers, drivers, vendors, and admins —
built with Flutter and Firebase.

## Structure

- `mobile/` — Flutter client app (all four roles share one codebase, routed by role)
- `functions/` — Firebase Cloud Functions (TypeScript) — order-lifecycle triggers and callables
- `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json`, `storage.rules` — Firebase project config

## Setup

This app is wired up to the Firebase project `orient-food-9c1e0` (see `.firebaserc`). Firestore
(Native mode), Auth, and Storage are already provisioned on that project.

1. ✅ `flutterfire configure` has been run for `android`, `ios`, and `web`, generating
   `mobile/lib/firebase_options.dart` and `mobile/android/app/google-services.json`.
   `ios/Runner/GoogleService-Info.plist` was **not** generated — FlutterFire CLI can only embed it into
   the Xcode project from macOS. On a Mac, run `flutterfire configure -p orient-food-9c1e0 -y` from
   `mobile/` to fill it in before building for iOS.
2. Install Cloud Functions dependencies: `cd functions && npm install`.
3. Add a Maps API key for `google_maps_flutter` (Android: `mobile/android/app/src/main/AndroidManifest.xml`,
   iOS: `mobile/ios/Runner/AppDelegate.swift`).

To point this app at a different Firebase project instead, update `.firebaserc` and re-run
`flutterfire configure -p <project-id>`.

## Development

Run the Firebase emulator suite (Auth, Firestore, Functions, Storage) alongside the app for local development:

```
firebase emulators:start
```

Then run the Flutter app:

```
cd mobile
flutter run
```

## Data model

- `users/{uid}` — profile + `role` (`customer` | `driver` | `vendor` | `admin`)
- `vendors/{vendorId}` — storefront, owned by a `vendor` user; `menuItems` subcollection
- `drivers/{uid}` — availability + last known location
- `orders/{orderId}` — items, status, links to `customerId` / `vendorId` / `driverId`

Order status flows: `pending → accepted → preparing → readyForPickup → pickedUp → delivering → delivered`
(or `cancelled` at any point before `delivered`).
