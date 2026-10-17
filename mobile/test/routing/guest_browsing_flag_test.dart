import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/routing/app_router.dart';
import 'package:delivery_app/routing/session_redirect.dart';

// The flag is a compile-time constant, so what these tests see depends on how
// they were started:
//   flutter test test/routing/guest_browsing_flag_test.dart
//     → the default: off.
//   flutter test --dart-define=GUEST_BROWSING=true test/routing/guest_browsing_flag_test.dart
//     → turned on locally.
// Run the rest of the suite without the define: its default-behaviour tests
// expect guest browsing off.
const _defined = bool.hasEnvironment(guestBrowsingDefine);
const _definedAs = bool.fromEnvironment(guestBrowsingDefine);

void main() {
  test('the define is named GUEST_BROWSING', () {
    expect(guestBrowsingDefine, 'GUEST_BROWSING');
  });

  test(
    'off when no --dart-define is passed (a normal build is unchanged)',
    () {
      expect(guestBrowsingEnabledByDefault, isFalse);
    },
    skip: _defined ? 'started with --dart-define=$guestBrowsingDefine' : false,
  );

  test(
    'on locally with --dart-define=GUEST_BROWSING=true (outside release builds)',
    () {
      expect(kReleaseMode, isFalse);
      expect(guestBrowsingEnabledByDefault, isTrue);
    },
    skip: _definedAs ? false : 'start with --dart-define=$guestBrowsingDefine=true to run',
  );

  test('the flag always matches the define outside release builds', () {
    expect(guestBrowsingEnabledByDefault, !kReleaseMode && _definedAs);
  });

  test('the router reads the flag through guestBrowsingEnabledProvider', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(guestBrowsingEnabledProvider), guestBrowsingEnabledByDefault);
  });

  test('sessionRedirect defaults to the flag', () {
    final guest = SessionRouteKey.of(const SessionGuest());
    expect(
      sessionRedirect(guest, homePath),
      sessionRedirect(guest, homePath, guestBrowsing: guestBrowsingEnabledByDefault),
    );
  });
}
