import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/vendor.dart';

const double productCardWidth = 148;

/// Small swipeable product tile for CustomerHomeScreen's horizontal feed —
/// image, item name, owning vendor's name (needed here since products from
/// several vendors are mixed in one row, unlike the old per-vendor list),
/// and price. Tapping opens that product's vendor (see [onTap]).
class ProductCard extends StatelessWidget {
  const ProductCard({
    required this.item,
    required this.vendorName,
    required this.currencyFormat,
    this.onTap,
    super.key,
  });

  final MenuItem item;
  final String vendorName;
  final NumberFormat currencyFormat;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: productCardWidth,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: item.imageUrl != null
                    ? Image.network(item.imageUrl!, fit: BoxFit.cover)
                    : Container(
                        color: colorScheme.surfaceContainerHighest,
                        child: Icon(
                          Icons.fastfood_outlined,
                          size: 32,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: textTheme.labelLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      vendorName,
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      currencyFormat.format(item.price),
                      style: textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
