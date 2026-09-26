import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/core/format/display_formatters.dart';
import 'package:delivery_app/core/theme/app_sizes.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart';
import 'package:delivery_app/features/driver/screens/driver_stats_screen.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/driver.dart';
import 'package:delivery_app/models/order.dart';

import '../../support/real_theme_harness.dart';
import 'driver_test_support.dart';

Future<void> _pumpHome(WidgetTester tester, LayoutConfig c, List<Object> overrides) async {
  await pumpWithRealTheme(tester, const DriverHomeScreen(),
      locale: c.locale, width: c.width, height: 800, textScale: c.textScale, overrides: overrides.cast());
  await tester.pumpAndSettle();
}

String _money(LayoutConfig c, num amount) =>
    NumberFormat.currency(locale: c.locale.languageCode, name: 'SYP').format(amount);

/// [finder] is laid out on one line (a price split across lines reads as
/// two numbers).
void _expectSingleLine(WidgetTester tester, Finder finder) {
  final paragraph = tester.renderObject<RenderParagraph>(finder);
  final text = paragraph.text.toPlainText();
  final boxes = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: text.length));
  expect(boxes.map((b) => b.top.round()).toSet().length, 1, reason: '"$text" wrapped');
}

/// [finder] is tappable, fully on screen horizontally, and at least 48px
/// tall.
void _expectReachable(WidgetTester tester, Finder finder, LayoutConfig c) {
  expect(finder.hitTestable(), findsOneWidget);
  final rect = tester.getRect(finder);
  expect(rect.left, greaterThanOrEqualTo(-0.5));
  expect(rect.right, lessThanOrEqualTo(c.width + 0.5));
  expect(rect.height, greaterThanOrEqualTo(AppSizes.minTapTarget - 0.5));
}

/// The AppBar [title] is shown with real room, not squeezed to a sliver.
void _expectReadableTitle(WidgetTester tester, String title) {
  final text = find.descendant(of: find.byType(AppBar), matching: find.text(title));
  expect(text, findsOneWidget);
  expect(tester.getSize(text).width, greaterThanOrEqualTo(100));
}

/// The Material button (any variant, e.g. OutlinedButton.icon) labeled
/// [label].
Finder _button(String label) =>
    find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

void _expectNoRawOrderId() {
  expect(find.textContaining(longOrderId, skipOffstage: false), findsNothing);
}

void main() {
  testWidgetsAcrossLayouts('queue: AppBar, cards, Accept', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pumpHome(tester, c, driverHomeOverrides(queue: [
      driverOrder(longOrderId, OrderStatus.readyForPickup),
      driverOrder('order-2', OrderStatus.readyForPickup, total: 25000),
    ]));

    _expectReadableTitle(tester, l10n.availableDeliveriesTitle);
    expect(find.byKey(const ValueKey('driver_available_switch')).hitTestable(), findsOneWidget);
    _expectReachable(tester, find.byKey(driverMoreMenuKey), c);

    _expectNoRawOrderId();
    final card = find.byKey(const ValueKey('driver_queue_$longOrderId'));
    expect(find.descendant(of: card, matching: find.text(l10n.orderLabel(displayOrderId(longOrderId)))),
        findsOneWidget);
    expect(find.descendant(of: card, matching: find.text(l10n.orderItemCount(16))), findsOneWidget);
    _expectSingleLine(tester, find.descendant(of: card, matching: find.text(_money(c, 15013000))));
    final accept = find.byKey(const ValueKey('driver_accept_$longOrderId'));
    await revealInHome(tester, accept);
    _expectReachable(tester, accept, c);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('"more" menu: stats, language, sign out', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pumpHome(tester, c, driverHomeOverrides());
    await tester.tap(find.byKey(driverMoreMenuKey));
    await tester.pumpAndSettle();
    for (final label in [l10n.driverStatsTitle, l10n.languageToggleTooltip, l10n.signOutTooltip]) {
      expect(find.text(label).hitTestable(), findsOneWidget, reason: label);
      expect(tester.getRect(find.text(label)).right, lessThanOrEqualTo(c.width));
    }
  }, textScales: sensitiveTextScales);

  for (final status in [OrderStatus.driverAssigned, OrderStatus.delivering]) {
    testWidgetsAcrossLayouts('active delivery (${status.name}): sections, items, actions', (tester, c) async {
      final l10n = lookupAppLocalizations(c.locale);
      final semantics = tester.ensureSemantics();
      await _pumpHome(
        tester,
        c,
        driverHomeOverrides(
          activeOrders: Stream.value(driverOrder(longOrderId, status, driverId: driverId)),
          picker: FakeProofPicker(result: File('proof.jpg')),
        ),
      );

      _expectReadableTitle(tester, l10n.activeDeliveryTitle);
      _expectNoRawOrderId();
      expect(find.text(l10n.orderLabel(displayOrderId(longOrderId))), findsOneWidget);
      final statusLabel = status == OrderStatus.driverAssigned
          ? l10n.orderStatusDriverAssigned
          : l10n.orderStatusDelivering;
      expect(find.text(statusLabel), findsOneWidget);

      final navigate = find.byKey(ValueKey(
          status == OrderStatus.driverAssigned ? 'navigate_to_pickup' : 'navigate_to_drop_off'));
      await revealInHome(tester, navigate);
      _expectReachable(tester, navigate, c);
      final call = _button(l10n.callCustomerButton);
      await revealInHome(tester, call);
      _expectReachable(tester, call, c);

      // Item names get the card's width (they had ~8px at 320 1.3x), and
      // every line total and the total to collect stay on one line.
      for (final name in [longAr, longEn]) {
        final text = find.text(name, skipOffstage: false);
        await revealInHome(tester, text);
        expect(tester.renderObject<RenderParagraph>(text).constraints.maxWidth, greaterThan(c.width * 0.6),
            reason: name);
      }
      final lineTotal = find.text(_money(c, 15000000), skipOffstage: false);
      await revealInHome(tester, lineTotal);
      _expectSingleLine(tester, lineTotal);
      final toCollect = find.text(_money(c, 15013000), skipOffstage: false);
      await revealInHome(tester, toCollect);
      _expectSingleLine(tester, toCollect);

      if (status == OrderStatus.delivering) {
        for (final key in ['driver_proof_camera', 'driver_proof_gallery']) {
          final button = find.byKey(ValueKey(key));
          await revealInHome(tester, button);
          _expectReachable(tester, button, c);
        }
        expect(find.bySemanticsLabel(l10n.proofNoPhotoLabel), findsOneWidget);
      }

      final advance = find.byKey(const ValueKey('driver_advance_button'));
      await revealInHome(tester, advance);
      _expectReachable(tester, advance, c);
      semantics.dispose();
    }, textScales: sensitiveTextScales);
  }

  testWidgetsAcrossLayouts('final delivery: proof picked, confirmation dialog fits', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    final semantics = tester.ensureSemantics();
    await _pumpHome(
      tester,
      c,
      driverHomeOverrides(
        activeOrders: Stream.value(driverOrder(longOrderId, OrderStatus.delivering, driverId: driverId)),
        picker: FakeProofPicker(result: File('proof.jpg')),
      ),
    );
    final gallery = find.byKey(const ValueKey('driver_proof_gallery'));
    await revealInHome(tester, gallery);
    await tester.tap(gallery);
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(l10n.proofPhotoAttachedLabel), findsOneWidget);

    final advance = find.byKey(const ValueKey('driver_advance_button'));
    await revealInHome(tester, advance);
    await tester.tap(advance);
    await tester.pumpAndSettle();
    expect(find.text(l10n.confirmDeliveredTitle), findsOneWidget);
    _expectReachable(tester, _button(l10n.confirmButton), c);
    expect(_button(l10n.cancelButton).hitTestable(), findsOneWidget);
    semantics.dispose();
  }, textScales: sensitiveTextScales);

  for (final (name, driver, title) in [
    ('pending', testDriver(status: ApprovalStatus.pending), 'driverPendingApprovalTitle'),
    ('rejected', testDriver(status: ApprovalStatus.rejected), 'driverNotApprovedTitle'),
    ('offline', testDriver(available: false), 'driverOfflineTitle'),
  ]) {
    testWidgetsAcrossLayouts('status view: $name', (tester, c) async {
      final l10n = lookupAppLocalizations(c.locale);
      await _pumpHome(tester, c, driverHomeOverrides(driver: driver));
      final key = name == 'offline' ? 'driver_offline' : 'driver_approval_$name';
      expect(find.byKey(ValueKey(key)), findsOneWidget);
      final expectedTitle = switch (title) {
        'driverPendingApprovalTitle' => l10n.driverPendingApprovalTitle,
        'driverNotApprovedTitle' => l10n.driverNotApprovedTitle,
        _ => l10n.driverOfflineTitle,
      };
      _expectReadableTitle(tester, expectedTitle);
      expect(find.text(l10n.availableDeliveriesTitle), findsNothing);
      if (name != 'offline') {
        expect(find.text(name == 'pending' ? l10n.vendorStatusPending : l10n.vendorStatusRejected), findsOneWidget);
      }
      _expectReachable(tester, find.byKey(driverMoreMenuKey), c);
    }, textScales: sensitiveTextScales);
  }

  testWidgetsAcrossLayouts('error state: driver account and queue failures offer retry', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await _pumpHome(tester, c, driverHomeOverrides(driverStream: Stream<Driver>.error(Exception('boom'))));
    expect(find.byKey(const ValueKey('driver_self_error')), findsOneWidget);
    _expectReachable(tester, _button(l10n.retryButton), c);
    expect(find.textContaining('boom'), findsNothing);
    _expectReadableTitle(tester, l10n.driverHomeTitle);

    await _pumpHome(
        tester, c, driverHomeOverrides(queueStream: Stream<List<DeliveryOrder>>.error(Exception('boom'))));
    expect(find.byKey(const ValueKey('driver_queue_error')), findsOneWidget);
    _expectReachable(tester, _button(l10n.retryButton), c);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('availability switch failure: snackbar fits', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    final firestore = ControlledFirestore(fail: true);
    await _pumpHome(tester, c, driverHomeOverrides(firestore: firestore));
    await tester.tap(find.byKey(const ValueKey('driver_available_switch')));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(tester.getRect(find.byType(SnackBar)).right, lessThanOrEqualTo(c.width));
    expect(find.textContaining('raw backend detail'), findsNothing);
    _expectReadableTitle(tester, l10n.availableDeliveriesTitle);
  }, textScales: sensitiveTextScales);

  testWidgetsAcrossLayouts('stats: stacked tiles, formatted count and earnings', (tester, c) async {
    final l10n = lookupAppLocalizations(c.locale);
    await pumpWithRealTheme(tester, const DriverStatsScreen(driverId: driverId),
        locale: c.locale,
        width: c.width,
        height: 800,
        textScale: c.textScale,
        overrides: [
          driverStatsProvider(driverId).overrideWith((ref) async => const DriverStats(deliveredCount: 1234567)),
          driverRatingProvider(driverId).overrideWith((ref) => Stream.value(
              const Driver(id: driverId, userId: driverId, isAvailable: true, ratingSum: 47, ratingCount: 10))),
        ]);
    await tester.pumpAndSettle();

    expect(find.text(NumberFormat.decimalPattern(c.locale.languageCode).format(1234567)), findsOneWidget);
    expect(find.text('1234567'), findsNothing);
    expect(find.text('4.7'), findsOneWidget);
    for (final key in ['driver_stat_delivered', 'driver_stat_earnings', 'driver_stat_rating']) {
      final tile = tester.getRect(find.byKey(ValueKey(key)));
      expect(tile.left, greaterThanOrEqualTo(0));
      expect(tile.right, lessThanOrEqualTo(c.width));
    }
    final earnings = find.descendant(
        of: find.byKey(const ValueKey('driver_stat_earnings')), matching: find.byType(Text)).at(0);
    _expectSingleLine(tester, earnings);
    expect(find.text(l10n.driverStatsTitle), findsOneWidget);
  }, textScales: sensitiveTextScales);
}
