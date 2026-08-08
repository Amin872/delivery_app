import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/preferences_provider.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/app_snackbar.dart';
import 'features/notifications/providers/push_notification_provider.dart';
import 'l10n/app_localizations.dart';
import 'routing/app_router.dart';

class DeliveryApp extends ConsumerWidget {
  const DeliveryApp({super.key});

  static final _scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final locale = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);

    // Keeps the signed-in user's FCM token registered for the app's
    // lifetime — see push_notification_provider.dart.
    ref.watch(pushNotificationSyncProvider);
    ref.listen(pushForegroundMessageProvider, (previous, next) {
      next.whenData((message) {
        final title = message.notification?.title;
        final body = message.notification?.body;
        if (title == null && body == null) return;
        // MaterialApp (and its Theme) doesn't exist yet at this point in the
        // widget tree — this widget builds it — so resolve the colors
        // directly from AppTheme/platform brightness instead of Theme.of.
        final isDark = themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                MediaQuery.platformBrightnessOf(context) == Brightness.dark);
        final colorScheme = (isDark ? AppTheme.dark : AppTheme.light).colorScheme;
        _scaffoldMessengerKey.currentState?.showSnackBar(
          buildAppSnackBar(colorScheme, [title, body].nonNulls.join(' — ')),
        );
      });
    });

    return MaterialApp.router(
      title: 'Delivery App',
      onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      supportedLocales: supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      routerConfig: router,
    );
  }
}
