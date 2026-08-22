import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/app.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/firebase_options.dart';
import 'package:delivery_app/models/app_user.dart';

/// The Android emulator's alias for the host machine's own localhost — where
/// `firebase emulators:start` actually runs. Real devices/iOS would need a
/// different host; this suite targets the Android emulator only (see plan).
const _emulatorHost = '10.0.2.2';

/// Points every Firebase client SDK the app uses at the local emulator
/// suite instead of the live `orient-food-9c1e0` project, so this suite
/// never touches production data. Call once, before pumping the app.
Future<void> connectToEmulators() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAuth.instance.useAuthEmulator(_emulatorHost, 9099);
  FirebaseFirestore.instance.useFirestoreEmulator(_emulatorHost, 8080);
  FirebaseFunctions.instance.useFunctionsEmulator(_emulatorHost, 5001);
  await FirebaseStorage.instance.useStorageEmulator(_emulatorHost, 9199);

  // The Android emulator's app storage (and Firebase Auth's cached session
  // within it) survives a plain emulator relaunch — only a full wipe clears
  // it. If a prior run ended mid-test (e.g. the emulator process itself
  // died), whoever was signed in then is still signed in now. Step 1 assumes
  // it starts on LoginScreen, so clear any leftover session directly via the
  // SDK rather than through UI, before the first widget is even pumped.
  if (FirebaseAuth.instance.currentUser != null) {
    await FirebaseAuth.instance.signOut();
  }
}

/// Builds the same widget tree `main.dart` does, minus the parts that don't
/// matter for a test (no need to re-fetch `SharedPreferences.getInstance()`
/// against real device storage). Locale is forced to English — the app
/// defaults to Arabic, and the suite's finders rely on stable English text.
Future<Widget> buildTestApp() async {
  SharedPreferences.setMockInitialValues({'locale': 'en'});
  final prefs = await SharedPreferences.getInstance();
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    child: const DeliveryApp(),
  );
}

/// Keeps pumping in small steps for up to [total]. Plain `pumpAndSettle()`
/// only waits for scheduled *frames* (animations) to stop — it can return
/// while a Firestore/Auth emulator round-trip (network I/O, not tied to
/// Flutter's frame scheduler) is still in flight, well before the
/// `currentAppUserProvider` listener that drives post-signup/sign-in
/// navigation has actually fired. A single fixed-duration pump sometimes
/// wasn't enough on a busy/cold emulator; polling in short steps up to a
/// generous ceiling gives slow round-trips room without slowing down the
/// common case where the response comes back quickly.
Future<void> _settleForBackend(WidgetTester tester, {Duration total = const Duration(seconds: 6)}) async {
  const step = Duration(milliseconds: 250);
  var elapsed = Duration.zero;
  while (elapsed < total) {
    await tester.pump(step);
    elapsed += step;
  }
}

String roleLabel(UserRole role) {
  switch (role) {
    case UserRole.customer:
      return 'Customer';
    case UserRole.driver:
      return 'Driver';
    case UserRole.vendor:
      return 'Vendor';
    case UserRole.admin:
      return 'Admin';
  }
}

/// Drives the real sign-up form starting from `LoginScreen`. `role` defaults
/// to `UserRole.customer`, which is `signup_screen.dart`'s own default, so
/// the role dropdown is only touched when a different role is requested.
Future<void> signUp(
  WidgetTester tester, {
  required String name,
  required String email,
  required String password,
  required String phone,
  UserRole role = UserRole.customer,
}) async {
  await tester.tap(find.byKey(const ValueKey('login_create_account_button')));
  await tester.pumpAndSettle();

  await tester.enterText(find.byKey(const ValueKey('signup_name_field')), name);
  await tester.enterText(find.byKey(const ValueKey('signup_email_field')), email);
  await tester.enterText(find.byKey(const ValueKey('signup_password_field')), password);
  await tester.enterText(find.byKey(const ValueKey('signup_phone_field')), phone);

  if (role != UserRole.customer) {
    await tester.tap(find.byKey(const ValueKey('signup_role_dropdown')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(roleLabel(role)).last);
    await tester.pumpAndSettle();
  }

  // The form lives in a SingleChildScrollView (CenteredScrollBody); on the
  // emulator's screen it's taller than the viewport, so the submit button
  // may not be scrolled into view yet — ensureVisible scrolls it there
  // before tap() computes a tap point, which a bare pumpAndSettle doesn't do.
  await tester.ensureVisible(find.byKey(const ValueKey('signup_submit_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('signup_submit_button')));
  await tester.pumpAndSettle();
  await _settleForBackend(tester);
}

/// Drives the real sign-in form. Assumes `LoginScreen` is already showing
/// (true right after `signOut`, or on a fresh app start with no session).
Future<void> signIn(WidgetTester tester, {required String email, required String password}) async {
  await tester.enterText(find.byKey(const ValueKey('login_email_field')), email);
  await tester.enterText(find.byKey(const ValueKey('login_password_field')), password);
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.byKey(const ValueKey('login_submit_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('login_submit_button')));
  await tester.pumpAndSettle();
  await _settleForBackend(tester);
}

/// Every role's home screen AppBar has exactly one `Icons.logout` action
/// (see `customer_home_screen.dart`/`vendor_dashboard_screen.dart`/
/// `driver_home_screen.dart`/`admin_dashboard_screen.dart`), so one finder
/// works everywhere without a role-specific key.
Future<void> signOut(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.logout));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 1200));
}

/// Fakes the image_picker platform channel so the proof-of-delivery photo
/// step (and any other image pick) doesn't need to drive an OS-native
/// gallery chooser — `WidgetTester` can't reach outside the Flutter widget
/// tree at all, so that dialog would otherwise hang the test forever.
/// Writes the bundled fixture PNG to the device's own temp storage and
/// returns that on-device path, exactly like a real pick would.
class FakeImagePicker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    final bytes = await rootBundle.load('integration_test/fixtures/test_photo.png');
    final file = File(
      '${Directory.systemTemp.path}/test_photo_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes.buffer.asUint8List());
    return XFile(file.path);
  }
}
