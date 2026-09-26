import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:delivery_app/features/customer/widgets/product_order_bar.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/vendor.dart';

import '../../support/real_theme_harness.dart';

// A large unit price so the running total is long (e.g. "1,450,000 SYP").
const _item = MenuItem(id: 'meal-family', vendorId: 'v', name: 'وجبة عائلية كبيرة', price: 145000, available: true);

Future<void> _pumpBar(WidgetTester tester, LayoutConfig config) async {
  await pumpWithRealTheme(
    tester,
    Scaffold(
      body: const SizedBox.expand(),
      bottomNavigationBar: ProductOrderBar(
        vendorId: 'v',
        vendorName: 'مطعم تجريبي',
        item: _item,
        currencyFormat: NumberFormat.currency(locale: config.locale.languageCode, name: 'SYP'),
      ),
    ),
    locale: config.locale,
    width: config.width,
    textScale: config.textScale,
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgetsAcrossLayouts(
    'ProductOrderBar: label, full price and both quantity buttons fit, even at quantity 10',
    (tester, config) async {
      await _pumpBar(tester, config);
      final l10n = lookupAppLocalizations(config.locale);

      // Raise the quantity to 10 → total 1,450,000 (longest realistic price).
      for (var i = 0; i < 9; i++) {
        await tester.tap(find.byIcon(Icons.add));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      final format = NumberFormat.currency(locale: config.locale.languageCode, name: 'SYP');
      final screen = Offset.zero & tester.view.physicalSize / tester.view.devicePixelRatio;
      for (final finder in [
        find.text(l10n.addToOrderButtonLabel),
        find.text(format.format(145000 * 10)),
        find.text('10'),
        find.byIcon(Icons.add),
        find.byIcon(Icons.remove),
      ]) {
        expect(finder, findsOneWidget);
        final rect = tester.getRect(finder);
        expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight - const Offset(0.01, 0.01)), isTrue,
            reason: '$finder is clipped off screen: $rect');
      }
      // Quantity buttons keep a full tap target.
      for (final icon in [Icons.add, Icons.remove]) {
        final button = find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton));
        expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
        expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      }
      // Western digits in both languages.
      expect(find.textContaining(RegExp('[\u0660-\u0669]')), findsNothing);
    },
    textScales: sensitiveTextScales,
  );
}
