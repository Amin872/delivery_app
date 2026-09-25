import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/formatters_provider.dart';
import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/services/firestore_service.dart';

/// Shared setup for the admin screen tests: the real FirestoreService over
/// an in-memory Firestore (so every admin stream runs its real query),
/// English, and a phone-width view by default (below AdminScaffold's
/// 840dp breakpoint, so the nav is the drawer).
final adminTestL10n = lookupAppLocalizations(const Locale('en'));

Future<void> pumpAdminScreen(
  WidgetTester tester,
  Widget home,
  FakeFirebaseFirestore db, {
  Size size = const Size(400, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      key: UniqueKey(),
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        firestoreServiceProvider.overrideWithValue(FirestoreService(firestore: db)),
        currencyFormatProvider.overrideWithValue(NumberFormat.currency(locale: 'en', name: 'SYP')),
        dateTimeFormatProvider.overrideWithValue(DateFormat('yyyy-MM-dd HH:mm')),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Adds a driver: a `users` doc (role driver) plus its `drivers` doc.
/// [approval] null leaves approvalStatus unset (a legacy driver doc).
Future<void> seedDriver(
  FakeFirebaseFirestore db,
  String id,
  String name, {
  String? approval,
  bool available = false,
}) async {
  await db.collection('users').doc(id).set({'email': '$id@example.com', 'displayName': name, 'role': 'driver'});
  await db.collection('drivers').doc(id).set({
    'userId': id,
    'isAvailable': available,
    if (approval != null) 'approvalStatus': approval,
  });
}
