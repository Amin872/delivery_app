import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/core/widgets/info_card.dart';
import 'package:delivery_app/core/widgets/state_views.dart';
import 'package:delivery_app/core/widgets/status_badge.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/order.dart';

import '../../support/real_theme_harness.dart';

void main() {
  testWidgetsAcrossLayouts('every order status renders as a chip, in a Wrap and a tight Row', (tester, config) async {
    await pumpWithRealTheme(
      tester,
      Scaffold(
        body: ListView(
          children: [
            Wrap(spacing: 4, runSpacing: 4, children: [for (final s in OrderStatus.values) OrderStatusChip(status: s)]),
            for (final s in ApprovalStatus.values) ApprovalStatusBadge(status: s),
            // A badge squeezed next to long text must ellipsise, not overflow.
            Row(children: [
              const Expanded(child: Text('A long title that takes most of the row width in a list tile')),
              Flexible(child: OrderStatusChip(status: OrderStatus.readyForPickup)),
            ]),
          ],
        ),
      ),
      locale: config.locale,
      width: config.width,
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(config.locale);
    expect(find.text(l10n.orderStatusDelivered), findsOneWidget);
  });

  testWidgetsAcrossLayouts('theme buttons are safe directly inside a Row (Phase 1 C1 guard)', (tester, config) async {
    await pumpWithRealTheme(
      tester,
      Scaffold(
        body: Column(children: [
          Row(children: [
            const Expanded(child: Text('Label')),
            TextButton(onPressed: () {}, child: const Text('Text')),
          ]),
          for (final button in [
            FilledButton(onPressed: () {}, child: const Text('Filled')),
            OutlinedButton(onPressed: () {}, child: const Text('Outlined')),
            ElevatedButton(onPressed: () {}, child: const Text('Elevated')),
          ])
            Row(children: [const Expanded(child: Text('Label')), button]),
        ]),
      ),
      locale: config.locale,
      width: config.width,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Text'));
    expect(tester.getSize(find.byType(FilledButton)).height, 48);
  });

  testWidgetsAcrossLayouts('EmptyState, ErrorState (with retry) and InfoCard', (tester, config) async {
    var retries = 0;
    await pumpWithRealTheme(
      tester,
      Scaffold(
        body: Column(children: [
          const Expanded(child: EmptyState(message: 'Nothing here yet', icon: Icons.inbox_outlined, title: 'Empty')),
          Expanded(child: ErrorState(error: const AppException('network-error'), onRetry: () => retries++)),
          const InfoCard(children: [Text('Row one'), Text('Row two')]),
        ]),
      ),
      locale: config.locale,
      width: config.width,
    );
    await tester.pumpAndSettle();
    final l10n = lookupAppLocalizations(config.locale);
    expect(find.text(l10n.networkErrorMessage), findsOneWidget);
    await tester.tap(find.text(l10n.retryButton));
    expect(retries, 1);
  });

  testWidgets('ErrorState without onRetry shows no retry button', (tester) async {
    await pumpWithRealTheme(tester, const Scaffold(body: ErrorState(error: AppException('unknown'))));
    expect(find.text(lookupAppLocalizations(const Locale('ar')).retryButton), findsNothing);
  });
}
