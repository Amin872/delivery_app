import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/features/auth/widgets/require_sign_in.dart';
import 'package:delivery_app/l10n/app_localizations.dart';
import 'package:delivery_app/models/app_user.dart';

final _l10n = lookupAppLocalizations(const Locale('en'));

const _customer =
    AppUser(id: 'c1', email: 'c@example.com', displayName: 'C', role: UserRole.customer);

class _Probe {
  final results = <bool>[];
  int launches = 0;
}

/// A button that runs [requireSignIn] and records what it returned.
Future<_Probe> _pump(WidgetTester tester, {AppUser? user, required SessionState session}) async {
  final probe = _Probe();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentAppUserProvider.overrideWith((ref) => Stream.value(user)),
        sessionProvider.overrideWithValue(session),
        signInLauncherProvider.overrideWithValue((context) => probe.launches++),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Consumer(
          builder: (context, ref, _) {
            // Screens that gate actions already watch the profile, as here.
            ref.watch(currentAppUserProvider);
            return Scaffold(
              body: TextButton(
                onPressed: () async => probe.results.add(await requireSignIn(context, ref)),
                child: const Text('protected action'),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return probe;
}

Finder get _prompt => find.byKey(const ValueKey('sign_in_prompt'));

void main() {
  testWidgets('a signed-in user passes straight through, with no prompt', (tester) async {
    final probe = await _pump(tester, user: _customer, session: const SessionReady(_customer));

    await tester.tap(find.text('protected action'));
    await tester.pumpAndSettle();

    expect(_prompt, findsNothing);
    expect(probe.results, [true]);
    expect(probe.launches, 0);
  });

  testWidgets('a guest gets a clear prompt; Cancel does nothing else', (tester) async {
    final probe = await _pump(tester, session: const SessionGuest());

    await tester.tap(find.text('protected action'));
    await tester.pumpAndSettle();
    expect(_prompt, findsOneWidget);
    expect(find.text(_l10n.signInRequiredTitle), findsOneWidget);
    expect(find.text(_l10n.signInRequiredMessage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sign_in_prompt_cancel')));
    await tester.pumpAndSettle();

    expect(_prompt, findsNothing);
    expect(probe.results, [false]);
    expect(probe.launches, 0);
  });

  testWidgets('a guest who chooses Sign in is taken to the sign-in flow', (tester) async {
    final probe = await _pump(tester, session: const SessionGuest());

    await tester.tap(find.text('protected action'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('sign_in_prompt_confirm')));
    await tester.pumpAndSettle();

    expect(_prompt, findsNothing);
    expect(probe.results, [false]);
    expect(probe.launches, 1);
  });

  for (final (label, session) in <(String, SessionState)>[
    ('unresolved auth', const SessionUnresolved()),
    ('a loading profile', const SessionProfileLoading('c1')),
    ('a missing profile', const SessionProfileMissing('c1')),
    ('an auth error', const SessionError(AppException('network-error'), StackTrace.empty)),
    (
      'a profile error',
      const SessionError(AppException('permission-denied'), StackTrace.empty, uid: 'c1'),
    ),
  ]) {
    testWidgets('$label is never treated as a guest: no prompt, action refused',
        (tester) async {
      final probe = await _pump(tester, session: session);

      await tester.tap(find.text('protected action'));
      await tester.pumpAndSettle();

      expect(_prompt, findsNothing);
      expect(probe.results, [false]);
      expect(probe.launches, 0);
    });
  }
}
