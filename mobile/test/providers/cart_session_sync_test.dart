import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/features/auth/providers/session_provider.dart';
import 'package:delivery_app/features/customer/providers/cart_provider.dart';
import 'package:delivery_app/features/customer/providers/cart_session_sync.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/vendor.dart';

AppUser _user(String uid, UserRole role, {String? displayName}) =>
    AppUser(id: uid, email: '$uid@example.com', displayName: displayName ?? uid, role: role);

SessionState _ready(String uid, [UserRole role = UserRole.customer]) =>
    SessionReady(_user(uid, role));

const _authError = SessionError(AppException('network-error'), StackTrace.empty);
SessionState _profileError(String uid) =>
    SessionError(const AppException('permission-denied'), StackTrace.empty, uid: uid);

const _falafel =
    MenuItem(id: 'falafel', vendorId: 'v1', name: 'Falafel wrap', price: 2000, available: true);

/// A real [CartController] that also counts [clear] calls.
class _RecordingCart extends CartController {
  int clears = 0;

  @override
  void clear() {
    clears++;
    super.clear();
  }
}

/// The session the sync provider sees; tests drive it directly.
final _session = StateProvider<SessionState>((ref) => const SessionUnresolved());

class _Harness {
  _Harness() {
    container = ProviderContainer(overrides: [
      sessionProvider.overrideWith((ref) => ref.watch(_session)),
      cartProvider.overrideWith((ref) => cart),
    ]);
    addTearDown(container.dispose);
    // Keep the sync provider alive, as app.dart does.
    container.listen(cartSessionSyncProvider, (previous, next) {});
  }

  final cart = _RecordingCart();
  late final ProviderContainer container;

  CartState get contents => container.read(cartProvider);

  void addFalafel() => cart.addItem('v1', 'Falafel House', _falafel);

  Future<void> go(SessionState session) async {
    container.read(_session.notifier).state = session;
    await container.pump();
  }

  /// Applies each session in turn, letting the listener run after each.
  Future<void> goThrough(List<SessionState> sessions) async {
    for (final session in sessions) {
      await go(session);
    }
  }
}

void main() {
  group('cartOwnershipTransition (pure rule)', () {
    const guest = CartOwner.guest();

    test('unresolved and auth errors never clear and never change the owner', () {
      for (final owner in [guest, const CartOwner(uid: 'a', role: UserRole.customer)]) {
        for (final session in [const SessionUnresolved(), _authError]) {
          final t = cartOwnershipTransition(owner, session);
          expect(t.clearCart, isFalse, reason: '$owner → $session');
          expect(t.owner, owner, reason: '$owner → $session');
        }
      }
    });

    test('a guest cart is adopted by the first account, through loading and missing', () {
      for (final session in [
        const SessionProfileLoading('u'),
        const SessionProfileMissing('u'),
        _profileError('u'),
        _ready('u'),
      ]) {
        final t = cartOwnershipTransition(guest, session);
        expect(t.clearCart, isFalse, reason: '$session');
        expect(t.owner.uid, 'u', reason: '$session');
      }
    });

    test('sign-out clears and resets ownership; a guest staying a guest does not', () {
      final signedOut = cartOwnershipTransition(
        const CartOwner(uid: 'u', role: UserRole.customer),
        const SessionGuest(),
      );
      expect(signedOut.clearCart, isTrue);
      expect(signedOut.owner, guest);

      final stillGuest = cartOwnershipTransition(guest, const SessionGuest());
      expect(stillGuest.clearCart, isFalse);
      expect(stillGuest.owner, guest);
    });

    test('a different account clears at its first state, then owns the cart', () {
      const a = CartOwner(uid: 'a', role: UserRole.customer);
      for (final session in [
        const SessionProfileLoading('b'),
        const SessionProfileMissing('b'),
        _profileError('b'),
        _ready('b'),
      ]) {
        final t = cartOwnershipTransition(a, session);
        expect(t.clearCart, isTrue, reason: '$session');
        expect(t.owner.uid, 'b', reason: '$session');
      }
    });

    test('the same account loading, failing or updating its profile keeps the cart', () {
      const a = CartOwner(uid: 'a', role: UserRole.customer);
      for (final session in [
        const SessionProfileLoading('a'),
        const SessionProfileMissing('a'),
        _profileError('a'),
        _ready('a'),
        SessionReady(_user('a', UserRole.customer, displayName: 'Renamed')),
      ]) {
        final t = cartOwnershipTransition(a, session);
        expect(t.clearCart, isFalse, reason: '$session');
        expect(t.owner, a, reason: '$session');
      }
    });

    test('a ready vendor, driver or admin clears — once', () {
      for (final role in [UserRole.vendor, UserRole.driver, UserRole.admin]) {
        for (final from in [guest, const CartOwner(uid: 'u', role: UserRole.customer)]) {
          final first = cartOwnershipTransition(from, _ready('u', role));
          expect(first.clearCart, isTrue, reason: '$from → $role');
          expect(first.owner, CartOwner(uid: 'u', role: role));

          final again = cartOwnershipTransition(first.owner, _ready('u', role));
          expect(again.clearCart, isFalse, reason: 'repeated $role');
          expect(again.owner, first.owner);
        }
      }
    });
  });

  group('cartSessionSyncProvider (actual cart contents)', () {
    test('1. guest → customer keeps and adopts the guest cart', () async {
      final h = _Harness();
      await h.go(const SessionGuest());
      h.addFalafel();

      await h.goThrough([const SessionProfileLoading('u'), _ready('u')]);

      expect(h.contents.lines.keys, ['falafel']);
      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);

      // Now owned by u: signing out clears it.
      await h.go(const SessionGuest());
      expect(h.contents.isEmpty, isTrue);
    });

    test('2. customer → guest (sign-out or account deletion) clears', () async {
      final h = _Harness();
      await h.go(_ready('u'));
      h.addFalafel();

      await h.go(const SessionGuest());

      expect(h.contents.isEmpty, isTrue);
      expect(h.cart.clears, 1);
    });

    test('3. customer A → customer B clears before B can use it', () async {
      final h = _Harness();
      await h.go(_ready('a'));
      h.addFalafel();

      await h.go(const SessionProfileLoading('b'));
      expect(h.contents.isEmpty, isTrue, reason: 'cleared at B\'s first state');

      await h.go(_ready('b'));
      expect(h.contents.isEmpty, isTrue);
      expect(h.cart.clears, 1);

      // B's own cart is now B's: B's profile updates keep it.
      h.addFalafel();
      await h.go(SessionReady(_user('b', UserRole.customer, displayName: 'B2')));
      expect(h.contents.itemCount, 1);
    });

    test('4. A → auth error → B clears once B is confirmed', () async {
      final h = _Harness();
      await h.go(_ready('a'));
      h.addFalafel();

      await h.go(_authError);
      expect(h.contents.itemCount, 1, reason: 'an auth error alone never clears');

      await h.go(_ready('b'));
      expect(h.contents.isEmpty, isTrue);
      expect(h.cart.clears, 1);
    });

    test('5. A → auth error → A keeps the cart', () async {
      final h = _Harness();
      await h.go(_ready('a'));
      h.addFalafel();

      await h.goThrough([_authError, _ready('a')]);

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    test('6. guest → loading → missing profile → ready customer (sign-up) keeps it', () async {
      final h = _Harness();
      await h.go(const SessionGuest());
      h.addFalafel();

      await h.goThrough([
        const SessionProfileLoading('new'),
        const SessionProfileMissing('new'),
        _ready('new'),
      ]);

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    test('7. unresolved → ready keeps whatever the cart holds', () async {
      final h = _Harness();
      h.addFalafel(); // not realistic at launch, but it must not be wiped

      await h.go(_ready('u'));

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    test('unresolved → guest does not clear a new guest cart', () async {
      final h = _Harness();
      await h.go(const SessionGuest());
      h.addFalafel();

      await h.go(const SessionGuest());

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    test('8. a profile error or missing profile alone does not clear', () async {
      final h = _Harness();
      await h.go(_ready('u'));
      h.addFalafel();

      await h.goThrough([_profileError('u'), const SessionProfileMissing('u'), _ready('u')]);

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    test('9. a same-UID profile-only update keeps the cart', () async {
      final h = _Harness();
      await h.go(_ready('u'));
      h.addFalafel();

      await h.go(SessionReady(_user('u', UserRole.customer, displayName: 'Renamed')));

      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 0);
    });

    for (final role in [UserRole.vendor, UserRole.driver, UserRole.admin]) {
      test('10. guest → ready $role clears the guest cart', () async {
        final h = _Harness();
        await h.go(const SessionGuest());
        h.addFalafel();

        await h.goThrough([const SessionProfileLoading('u'), _ready('u', role)]);

        expect(h.contents.isEmpty, isTrue);
        expect(h.cart.clears, 1);
      });

      test('10. ready customer → ready $role (same account) clears', () async {
        final h = _Harness();
        await h.go(_ready('u'));
        h.addFalafel();

        await h.go(_ready('u', role));

        expect(h.contents.isEmpty, isTrue);
        expect(h.cart.clears, 1);
      });
    }

    test('11. a ready non-customer never ends up holding a customer cart', () async {
      final h = _Harness();
      await h.go(_ready('c'));
      h.addFalafel();

      // Every route into a vendor session drops the customer's items.
      await h.goThrough([
        const SessionGuest(),
        const SessionProfileLoading('v'),
        _ready('v', UserRole.vendor),
      ]);
      expect(h.contents.isEmpty, isTrue);

      await h.go(_ready('c'));
      h.addFalafel();
      await h.go(_ready('c', UserRole.vendor));
      expect(h.contents.isEmpty, isTrue);
    });

    test('12. repeated emissions clear once and keep the right owner', () async {
      final h = _Harness();
      await h.go(_ready('a'));
      h.addFalafel();

      // Switching to B, with B's states repeated.
      await h.goThrough([
        const SessionProfileLoading('b'),
        const SessionProfileLoading('b'),
        _ready('b'),
        _ready('b'),
        SessionReady(_user('b', UserRole.customer, displayName: 'B again')),
      ]);
      expect(h.cart.clears, 1);

      // Ownership is B's, not A's: B's cart survives B's own repeats…
      h.addFalafel();
      await h.goThrough([_ready('b'), const SessionProfileLoading('b'), _ready('b')]);
      expect(h.contents.itemCount, 1);
      expect(h.cart.clears, 1);

      // …and a vendor repeated clears only once.
      await h.goThrough([_ready('b', UserRole.vendor), _ready('b', UserRole.vendor)]);
      expect(h.cart.clears, 2);
      expect(h.contents.isEmpty, isTrue);
    });
  });
}
