import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/format/display_formatters.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/adaptive_label_value.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import 'cart_add_flow.dart';
import 'most_ordered_card.dart'
    show mostOrderedAccentBackground, mostOrderedAccentForeground, orderAccentBackground;

/// Fixed bottom bar of `ProductDetailsSheet`: an "Add to order · price" pill
/// and a quantity pill, both at least [AppSizes.largeButtonHeight] tall and
/// free to grow with the text scale. Deliberately a *local* quantity
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
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: AppSizes.largeButtonHeight),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.xs,
                      ),
                      child: AdaptiveLabelValue(
                        label: l10n.addToOrderButtonLabel,
                        value: totalPrice,
                        style: textTheme.titleSmall?.copyWith(
                          color: VendorPalette.background,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
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
                constraints: const BoxConstraints(minHeight: AppSizes.largeButtonHeight),
                padding: const EdgeInsetsDirectional.symmetric(horizontal: AppSpacing.xs),
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
                    // Grows with the digits and the text scale (a fixed
                    // width clipped "99" at larger text sizes).
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: AppSizes.iconLarge),
                      child: Text(
                        formatCount(_quantity, Localizations.localeOf(context).toString()),
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
