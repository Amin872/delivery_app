import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers/preferences_provider.dart';
import 'core/theme/app_theme.dart';
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
        _scaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(content: Text([title, body].nonNulls.join(' — '))),
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
