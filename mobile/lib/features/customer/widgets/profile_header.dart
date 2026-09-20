import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';

/// "قسم الملف الشخصي" — a titled card summarizing the signed-in user, shown
/// at the top of [AccountScreen]. Purely theme-agnostic (reads
/// `Theme.of(context)` only, same as [AccountMenuSection]) so it renders
/// correctly regardless of which ambient theme its parent screen applies —
/// no colors are hardcoded here.
///
/// No photo-upload field exists on [AppUser] yet, so this deliberately never
/// renders a network image (that would mean either a fabricated URL or a
/// whole new storage/upload feature outside this screen's scope); an
/// initials avatar is a real, always-available representation of the
/// signed-in user instead.
class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    required this.displayName,
    required this.email,
    required this.onEditTap,
    this.phoneNumber,
    super.key,
  });

  final String displayName;
  final String email;
  final String? phoneNumber;
  final VoidCallback onEditTap;

  String get _initials {
    final parts = displayName.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    final first = parts.first.substring(0, 1);
    final last = parts.length > 1 ? parts.last.substring(0, 1) : '';
    return (first + last).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: 4, right: 4),
            child: Text(
              l10n.profileSectionTitle,
              style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: AppRadius.large,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: colorScheme.primary, shape: BoxShape.circle),
                  child: Text(
                    _initials,
                    style: textTheme.headlineSmall?.copyWith(color: colorScheme.onPrimary),
                  ),
                ),
                const SizedBox(width: AppSpacing.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: textTheme.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        email,
                        style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phoneNumber != null) ...[
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.phone_outlined, size: 14, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                phoneNumber!,
                                style: textTheme.bodySmall
                                    ?.copyWith(color: colorScheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  onPressed: onEditTap,
                  tooltip: l10n.editProfileButton,
                  icon: const Icon(Icons.edit_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.06, end: 0, curve: Curves.easeOut);
  }
}
