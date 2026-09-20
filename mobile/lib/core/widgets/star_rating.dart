import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Read-only star row for showing a `Vendor`/`Driver`'s `averageRating`.
/// Rounds to the nearest whole star rather than rendering half-stars, which
/// is precise enough for a 1-5 aggregate and keeps this a plain `Icon` row.
class StarRatingDisplay extends StatelessWidget {
  const StarRatingDisplay({
    required this.rating,
    this.count,
    this.size = 16,
    super.key,
  });

  /// Null renders all five stars outlined with no numeric label — used for
  /// a vendor/driver that hasn't been rated yet.
  final double? rating;
  final int? count;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filled = rating == null ? 0 : rating!.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Icon(
            i < filled ? Icons.star : Icons.star_border,
            color: colorScheme.primary,
            size: size,
          ),
        if (rating != null) ...[
          const SizedBox(width: 4),
          Text(
            count != null ? '${rating!.toStringAsFixed(1)} ($count)' : rating!.toStringAsFixed(1),
            style: TextStyle(fontSize: size * 0.75, color: colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Tappable 1-5 star picker for submitting a rating.
class StarRatingInput extends StatelessWidget {
  const StarRatingInput({
    required this.value,
    required this.onChanged,
    this.size = 32,
    this.keyPrefix,
    super.key,
  });

  final int value;
  final ValueChanged<int> onChanged;
  final double size;

  /// When set, each star gets its own `ValueKey('${keyPrefix}_star_N')` so
  /// integration tests can tap a specific star of a specific rating row
  /// (e.g. two `StarRatingInput`s side by side in `RateOrderDialog`).
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            key: keyPrefix == null ? null : ValueKey('${keyPrefix}_star_$i'),
            icon: AnimatedScale(
              scale: i <= value ? 1.15 : 1.0,
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              child: Icon(
                i <= value ? Icons.star : Icons.star_border,
                color: colorScheme.primary,
                size: size,
              ),
            ),
            onPressed: () {
              HapticFeedback.selectionClick();
              onChanged(i);
            },
          ),
      ],
    );
  }
}
