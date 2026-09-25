import 'dart:async';

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:delivery_app/core/providers/preferences_provider.dart';
import 'package:delivery_app/features/admin/screens/admin_driver_detail_screen.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show firestoreServiceProvider;
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/services/firestore_service.dart';

/// Real FirestoreService over an in-memory Firestore (so the screen's own
/// streams work), with the approval write held open until each test
/// completes or fails it.
class _ControlledApprovalService extends FirestoreService {
  _ControlledApprovalService(this.firestore) : super(firestore: firestore);

  final FakeFirebaseFirestore firestore;
  final writes = <ApprovalStatus>[];
  final pending = Completer<void>();

  @override
  Future<void> setDriverApprovalStatus(String driverId, ApprovalStatus status) {
    writes.add(status);
    return pending.future;
  }
}

Future<_ControlledApprovalService> _pump(WidgetTester tester, ApprovalStatus status) async {
  final firestore = FakeFirebaseFirestore();
  await firestore.collection('users').doc('driver-1').set({
    'email': 'driver@example.com',
    'displayName': 'Driver One',
    'role': 'driver',
  });
  await firestore.collection('drivers').doc('driver-1').set({
    'userId': 'driver-1',
    'isAvailable': true,
    'ratingSum': 0,
    'ratingCount': 0,
    'approvalStatus': status.name,
  });
  final service = _ControlledApprovalService(firestore);

  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        firestoreServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const AdminDriverDetailScreen(driverId: 'driver-1'),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return service;
}

void main() {
  testWidgets('pending driver: shows the status and both Approve and Reject', (tester) async {
    await _pump(tester, ApprovalStatus.pending);

    expect(find.text('Approval'), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_approval_badge_pending')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_approve_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_reject_button')), findsOneWidget);
  });

  testWidgets('approved driver: only Reject is offered', (tester) async {
    await _pump(tester, ApprovalStatus.approved);

    expect(find.byKey(const ValueKey('driver_approval_badge_approved')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_approve_button')), findsNothing);
    expect(find.byKey(const ValueKey('driver_reject_button')), findsOneWidget);
  });

  testWidgets('rejected driver: only Approve is offered', (tester) async {
    await _pump(tester, ApprovalStatus.rejected);

    expect(find.byKey(const ValueKey('driver_approval_badge_rejected')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_approve_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('driver_reject_button')), findsNothing);
  });

  testWidgets('approve: busy blocks a second submission, then confirms', (tester) async {
    final service = await _pump(tester, ApprovalStatus.pending);

    await tester.tap(find.byKey(const ValueKey('driver_approve_button')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('driver_approve_button')));
    await tester.tap(find.byKey(const ValueKey('driver_reject_button')));
    await tester.pump();
    expect(service.writes, [ApprovalStatus.approved]);

    service.pending.complete();
    await tester.pumpAndSettle();
    expect(find.text('Driver approved.'), findsOneWidget);
  });

  testWidgets('a failed approval write shows a localized error', (tester) async {
    final service = await _pump(tester, ApprovalStatus.pending);

    await tester.tap(find.byKey(const ValueKey('driver_reject_button')));
    await tester.pump();
    service.pending.completeError(Exception('permission-denied'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't update the driver's approval. Please try again."), findsOneWidget);
  });
}
