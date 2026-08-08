import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Shimmering placeholder rows shown in a StreamProvider/FutureProvider's
/// `loading:` branch on list-shaped screens — reads as "content is on its
/// way" instead of a bare spinner with no sense of the page's shape.
class ListSkeletonLoader extends StatelessWidget {
  const ListSkeletonLoader({this.itemCount = 6, this.itemHeight = 72, super.key});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: colorScheme.surfaceContainerHighest,
      highlightColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: itemCount,
        itemBuilder: (context, index) => Container(
          height: itemHeight,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// Shimmering placeholder for a [StatCard] pair — used above
/// [ListSkeletonLoader] on the vendor/driver stats screens while their
/// aggregation queries are in flight.
class StatCardRowSkeleton extends StatelessWidget {
  const StatCardRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: colorScheme.surfaceContainerHighest,
      highlightColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 110,
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 110,
              decoration:
                  BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }
}
