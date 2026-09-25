import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';

/// Reached via the bell icon in [CustomerHomeScreen]'s header. There's no
/// persisted per-user notification history in this app today — FCM push
/// delivery (see `push_notification_provider.dart`) is fire-and-forget, shown
/// as a snackbar while foregrounded — so this is an honest empty state
/// rather than fabricated notification content, matching the app's existing
/// "nothing here yet" screens (My Orders, Reviews).
///
/// Same [VendorPalette] theme as CustomerHomeScreen, whose header this
/// screen is reached from.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.notificationsTitle),
        ),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.notifications_none_outlined,
                size: 48,
                color: VendorPalette.textMuted,
              ),
              const SizedBox(height: 12),
              Text(
                l10n.noNotificationsMessage,
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
