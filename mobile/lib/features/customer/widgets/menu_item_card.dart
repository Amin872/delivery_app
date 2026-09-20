import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../models/vendor.dart';
import 'most_ordered_card.dart' show mostOrderedAccentForeground;

/// Per-item row for VendorMenuScreen's normal (non-"most ordered") menu
/// sections — measured pixel-for-pixel from the reference: no card surface,
/// no border, no shadow, the page's own dark background shows straight
/// through (unlike the earlier `Card`-based design). A rectangular
/// ~120x80dp image sits on the physical left, name/description/price fill
/// the rest on the right; rows are separated by a hairline divider the
/// caller (`VendorMenuScreen`) draws between items, not by this widget,
/// since the divider must span the *list's* row width consistently rather
/// than being re-derived per card. There is deliberately no add-to-cart
/// control here anymore — tapping anywhere on the row opens
/// `ProductDetailsSheet` via [onTap], which is now the only way to add this
/// item (see `ProductOrderBar`).
class MenuItemCard extends StatelessWidget {
  const MenuItemCard({
    required this.item,
    required this.currencyFormat,
    this.onTap,
    super.key,
  });

  final MenuItem item;
  final NumberFormat currencyFormat;
  final VoidCallback? onTap;

  static const double _imageWidth = 120;
  static const double _imageHeight = 80;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.name,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: item.available ? VendorPalette.textPrimary : VendorPalette.textMuted,
                    ),
                  ),
                  if (item.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.description!,
                      style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Text(
                    currencyFormat.format(item.price),
                    style: textTheme.titleSmall
                        ?.copyWith(color: mostOrderedAccentForeground, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            item.imageUrl != null
                ? AppNetworkImage(
                    imageUrl: item.imageUrl!,
                    width: _imageWidth,
                    height: _imageHeight,
                    borderRadius: BorderRadius.circular(AppRadius.mediumValue),
                  )
                : ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.mediumValue),
                    child: SizedBox(
                      width: _imageWidth,
                      height: _imageHeight,
                      child: Container(
                        color: VendorPalette.surfaceContainer,
                        child: Icon(Icons.fastfood_outlined, color: VendorPalette.textMuted),
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
}
