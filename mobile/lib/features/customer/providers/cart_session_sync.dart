import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import '../../auth/providers/session_provider.dart';
import 'cart_provider.dart';

/// Who the in-memory cart belongs to. [uid] null is a guest's cart — owned
/// by nobody yet, so the first account that signs in adopts it. [role] is
/// known once that account's profile is ready.
@immutable
class CartOwner {
  const CartOwner({this.uid, this.role});

  const CartOwner.guest() : this();

  final String? uid;
  final UserRole? role;

  @override
  bool operator ==(Object other) =>
      other is CartOwner && other.uid == uid && other.role == role;

  @override
  int get hashCode => Object.hash(uid, role);

  @override
  String toString() => 'CartOwner(uid: $uid, role: $role)';
}

/// The result of [cartOwnershipTransition]: the cart's next owner, and
/// whether the cart must be emptied first.
typedef CartOwnershipTransition = ({CartOwner owner, bool clearCart});

/// Pure rule for what a session change means for the cart.
///
/// Keeps the cart when:
/// - nothing is known yet, or auth failed (unresolved, auth error) — never
///   clear on a state that carries no account;
/// - a guest's cart is adopted by the first account that signs in (sign-in
///   or sign-up, through loading and a briefly missing profile);
/// - the same account loads, fails, recovers or updates its profile.
///
/// Clears the cart when:
/// - a signed-in account signs out (or is deleted) and a guest remains;
/// - a different account appears — at its first state, before it can use
///   the cart (an auth error in between doesn't hide the switch, since it
///   leaves the owner as it was);
/// - a ready vendor, driver or admin takes over: they can't order, so a
///   customer's cart must not linger for later.
///
/// Repeating the same session (or a profile-only update) changes nothing,
/// so a cart is never cleared twice for one transition.
CartOwnershipTransition cartOwnershipTransition(CartOwner owner, SessionState next) {
  final keep = (owner: owner, clearCart: false);
  switch (next) {
    case SessionUnresolved():
      return keep;
    case SessionGuest():
      return owner.uid == null ? keep : (owner: const CartOwner.guest(), clearCart: true);
    case SessionError(uid: null):
      return keep;
    case SessionProfileLoading(:final uid) ||
          SessionProfileMissing(:final uid) ||
          SessionError(uid: final String uid):
      if (owner.uid != null && owner.uid != uid) {
        return (owner: CartOwner(uid: uid), clearCart: true);
      }
      // Adopting a guest's cart, or the same account mid-load / failing
      // (its role, if already known, is kept).
      final role = owner.uid == uid ? owner.role : null;
      return (owner: CartOwner(uid: uid, role: role), clearCart: false);
    case SessionReady(:final user):
      final readyOwner = CartOwner(uid: user.id, role: user.role);
      if (owner.uid != null && owner.uid != user.id) {
        return (owner: readyOwner, clearCart: true);
      }
      if (user.role != UserRole.customer && owner != readyOwner) {
        return (owner: readyOwner, clearCart: true);
      }
      return (owner: readyOwner, clearCart: false);
  }
}

/// Keeps the cart isolated per account by applying [cartOwnershipTransition]
/// to every session change and emptying the cart when it says so. Has no
/// value of its own; `app.dart` watches it so it lives as long as the app.
/// The cart itself stays independent of auth (see cart_provider.dart).
final cartSessionSyncProvider = Provider<void>((ref) {
  // Whoever is there when the app starts owns whatever the cart holds (it's
  // empty at launch: the cart isn't persisted). No clearing during build.
  var owner = cartOwnershipTransition(const CartOwner.guest(), ref.read(sessionProvider)).owner;
  ref.listen<SessionState>(sessionProvider, (previous, next) {
    final transition = cartOwnershipTransition(owner, next);
    owner = transition.owner;
    if (transition.clearCart) ref.read(cartProvider.notifier).clear();
  });
});
