import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Local-only switch for browsing the app against the Firebase Emulator
/// Suite (`firebase emulators:start`, ports from the repo-root firebase.json)
/// instead of the live `delivery-app-syria-2026` project:
///
///   flutter run -d emulator-5554 --dart-define=USE_FIREBASE_EMULATORS=true
///
/// A compile-time constant that defaults to false, and main.dart also
/// ignores it in release mode — so store builds always talk to production.
const bool useFirebaseEmulators = bool.fromEnvironment('USE_FIREBASE_EMULATORS');

/// Where the emulators are reachable from the running app: the host machine's
/// own localhost on web, and the Android emulator's alias for it (10.0.2.2)
/// otherwise. Real devices/iOS would need a different host.
String get firebaseEmulatorHost => kIsWeb ? 'localhost' : '10.0.2.2';

/// Points every Firebase client SDK the app uses at the local emulator suite.
/// Call once, right after `Firebase.initializeApp` and before any Firebase
/// access. Shared by main.dart and integration_test/test_helpers.dart.
Future<void> connectFirebaseEmulators({String? host}) async {
  final emulatorHost = host ?? firebaseEmulatorHost;
  await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(emulatorHost, 5001);
  await FirebaseStorage.instance.useStorageEmulator(emulatorHost, 9199);
}
