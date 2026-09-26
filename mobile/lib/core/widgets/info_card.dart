import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_radius.dart';
import '../theme/app_spacing.dart';

/// Full-width grouped-details surface (a titled block of label/value rows
/// on detail screens). Children are laid out top-to-bottom, start-aligned.
class InfoCard extends StatelessWidget {
  const InfoCard({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppPalette.surfaceContainer,
        borderRadius: AppRadius.large,
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }
}
