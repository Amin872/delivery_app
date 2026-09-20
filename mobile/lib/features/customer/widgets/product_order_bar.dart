import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import 'cart_add_flow.dart';
import 'most_ordered_card.dart'
    show mostOrderedAccentBackground, mostOrderedAccentForeground, orderAccentBackground;

/// Fixed bottom bar of `ProductDetailsSheet` — measured from the reference
/// (RGB(113,210,246) fill, RGB(1,15,21) text, 56dp pill height, 16dp outer
/// margin, 8dp gap between the two pills). Deliberately a *local* quantity
/// picker (starts at 1, independent of the cart) rather than reusing
/// `CartQuantityControl`: this bar decides how many units to commit in one
/// "Add to order" tap, it doesn't mirror the cart's live quantity the way
/// the vertical/horizontal card controls do.

class ProductOrderBar extends ConsumerStatefulWidget {
  const ProductOrderBar({
    required this.vendorId,
    required this.vendorName,
    required this.item,
    required this.currencyFormat,
    super.key,
  });

  final String vendorId;
  final String vendorName;
  final MenuItem item;
  final NumberFormat currencyFormat;

  @override
  ConsumerState<ProductOrderBar> createState() => _ProductOrderBarState();
}

class _ProductOrderBarState extends ConsumerState<ProductOrderBar> {
  int _quantity = 1;

  void _increment() {
    HapticFeedback.selectionClick();
    setState(() => _quantity = (_quantity + 1).clamp(1, 99));
  }

  void _decrement() {
    HapticFeedback.selectionClick();
    setState(() => _quantity = (_quantity - 1).clamp(1, 99));
  }

  Future<void> _addToOrder() async {
    await addToCartWithVendorSwitchConfirm(
      context,
      ref,
      vendorId: widget.vendorId,
      vendorName: widget.vendorName,
      item: widget.item,
      quantity: _quantity,
    );
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final totalPrice = widget.currencyFormat.format(widget.item.price * _quantity);

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.md,
        ),
        child: Row(
          children: [
            Expanded(
              child: Material(
                color: orderAccentBackground,
                borderRadius: AppRadius.pill,
                child: InkWell(
                  borderRadius: AppRadius.pill,
                  onTap: widget.item.available ? _addToOrder : null,
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.addToOrderButtonLabel,
                          style: textTheme.titleSmall?.copyWith(
                            color: VendorPalette.background,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          totalPrice,
                          style: textTheme.titleSmall?.copyWith(
                            color: VendorPalette.background,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Material(
              color: mostOrderedAccentBackground,
              borderRadius: AppRadius.pill,
              child: Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  // First child renders at the RTL *start* (right) — source
                  // order [minus, count, plus] puts "+" physically on the
                  // left and "-" physically on the right, matching the
                  // reference exactly (and the existing horizontal
                  // CartQuantityControl uses this same source order).
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove, color: mostOrderedAccentForeground),
                      onPressed: _decrement,
                    ),
                    SizedBox(
                      width: 20,
                      child: Text(
                        '$_quantity',
                        textAlign: TextAlign.center,
                        style: textTheme.titleSmall
                            ?.copyWith(color: mostOrderedAccentForeground, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, color: mostOrderedAccentForeground),
                      onPressed: _increment,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
