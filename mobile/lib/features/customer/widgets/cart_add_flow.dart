import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/confirm_dialog.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../providers/cart_provider.dart';

/// Adds [item] to the cart for (`vendorId`/`vendorName`), confirming with
/// the user first if the cart already holds a different vendor's items —
/// shared by every screen that can add a product to the cart for this
/// vendor (`VendorMenuScreen`'s menu sections, `MostOrderedScreen`'s full
/// grid, and `ProductDetailsSheet`'s order bar), so the switch-vendor
/// confirmation flow lives in exactly one place.
///
/// [quantity] (default 1, matching every pre-existing call site exactly)
/// lets `ProductOrderBar`'s local quantity stepper commit more than one unit
/// in a single call — `addItem` itself only ever adds one, so this tops the
/// line up to the right count via `setQuantity` afterward rather than
/// duplicating CartController's increment logic here.
Future<void> addToCartWithVendorSwitchConfirm(
  BuildContext context,
  WidgetRef ref, {
  required String vendorId,
  required String vendorName,
  required MenuItem item,
  int quantity = 1,
}) async {
  final notifier = ref.read(cartProvider.notifier);
  final state = ref.read(cartProvider);

  if (state.vendorId != null && state.vendorId != vendorId) {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.switchVendorConfirmTitle,
      message: l10n.switchVendorConfirmMessage,
    );
    if (confirmed != true) return;
    notifier.replaceWithItem(vendorId, vendorName, item);
    if (quantity > 1) notifier.setQuantity(item.id, quantity);
    return;
  }

  final existing = state.lines[item.id]?.quantity ?? 0;
  notifier.addItem(vendorId, vendorName, item);
  if (quantity > 1) notifier.setQuantity(item.id, existing + quantity);
}
