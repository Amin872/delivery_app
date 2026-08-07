# Delivery App

A delivery marketplace app with three roles — customers, drivers, and vendors —
built with Flutter and Firebase.

## Structure

- `mobile/` — Flutter client app (all three roles share one codebase, routed by role)
- `functions/` — Firebase Cloud Functions (TypeScript) — order-lifecycle triggers and callables
- `firebase.json`, `.firebaserc`, `firestore.rules`, `firestore.indexes.json`, `storage.rules` — Firebase project config

## Setup

1. Create a Firebase project and replace the placeholder in `.firebaserc` with its project ID.
2. From `mobile/`, run `flutterfire configure` to generate `lib/firebase_options.dart` and the native
   platform config files (`google-services.json`, `GoogleService-Info.plist`).
3. Install Cloud Functions dependencies: `cd functions && npm install`.
4. Add a Maps API key for `google_maps_flutter` (Android: `mobile/android/app/src/main/AndroidManifest.xml`,
   iOS: `mobile/ios/Runner/AppDelegate.swift`).

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

- `users/{uid}` — profile + `role` (`customer` | `driver` | `vendor`)
- `vendors/{vendorId}` — storefront, owned by a `vendor` user; `menuItems` subcollection
- `drivers/{uid}` — availability + last known location
- `orders/{orderId}` — items, status, links to `customerId` / `vendorId` / `driverId`

Order status flows: `pending → accepted → preparing → readyForPickup → pickedUp → delivering → delivered`
(or `cancelled` at any point before `delivered`).
