import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/errors/guard.dart';
import '../models/app_user.dart';
import '../models/driver.dart';
import '../models/vendor.dart';

class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? firestore})
      : _auth = auth ?? FirebaseAuth.instance,
        _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  Stream<User?> get authStateChanges => guardStream(_auth.authStateChanges());

  User? get currentUser => _auth.currentUser;

  // A live listener, not a one-shot get() — right after signUp(), Auth's
  // authStateChanges fires as soon as the account is created, which is
  // *before* users/{uid} is written (see signUp's ordering note below). A
  // one-shot fetch issued at that instant would race the write and could
  // permanently resolve to "no profile found"; watching the doc lets the
  // UI pick up the write as soon as it lands instead of needing a retry.
  Stream<AppUser?> watchAppUser(String uid) => guardStream(
        _firestore.collection('users').doc(uid).snapshots().map(
              (doc) => doc.exists ? AppUser.fromMap(doc.id, doc.data()!) : null,
            ),
      );

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return guardFuture(() async {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      await _ensureUserProfile(uid: credential.user!.uid, email: email);
      return credential;
    });
  }

  // A signed-in Firebase Auth account can end up without a users/{uid}
  // doc — signUp() writes it last (see the ordering note there), so an
  // interruption between account creation and that write strands the
  // account; the shared Firebase project (see CLAUDE.md) also has
  // pre-existing accounts from its other app that never went through this
  // app's signUp() at all. Either way, _RoleGate has nothing to route on
  // and dead-ends on "No profile found" — so backfill a default customer
  // profile here instead, since customer is the only role safe to assume
  // for an account this app didn't itself provision as vendor/driver/admin.
  Future<void> _ensureUserProfile({required String uid, required String email}) async {
    final doc = _firestore.collection('users').doc(uid);
    if ((await doc.get()).exists) return;
    final appUser = AppUser(id: uid, email: email, displayName: email, role: UserRole.customer);
    await doc.set(appUser.toMap());
  }

  Future<AppUser> signUp({
    required String email,
    required String password,
    required String displayName,
    required UserRole role,
    String? phoneNumber,
  }) {
    return guardFuture(() async {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final uid = credential.user!.uid;
      final appUser = AppUser(
        id: uid,
        email: email,
        displayName: displayName,
        role: role,
        phoneNumber: phoneNumber,
      );

      // The role-specific doc is written and server-confirmed (awaited)
      // BEFORE users/{uid} — deliberately, and in this order. Writing
      // users/{uid} is what currentAppUserProvider's local-cache listener
      // picks up to route into e.g. VendorDashboardScreen — optimistically,
      // as soon as this write is issued, well before it's server-confirmed.
      // If vendors/{uid} were written second, the dashboard's first orders
      // query could reach the server before that doc exists, and its
      // ownership check (`get(vendors/{vendorId}).data.ownerId == ...`)
      // would fail with permission-denied. Writing it first and awaiting
      // server confirmation closes that race.
      if (role == UserRole.vendor) {
        final vendor = Vendor(
          id: uid,
          ownerId: uid,
          name: displayName,
          description: '',
          isOpen: false,
          approvalStatus: VendorApprovalStatus.pending,
        );
        await _firestore.collection('vendors').doc(uid).set(vendor.toMap());
      }

      // A driver's availability doc shares the user's uid as its id (matches
      // firestore.rules' isSelf(driverId) check) — without it, the first
      // location update (LocationService.publishDriverLocation) would fail
      // since there'd be nothing to update. Same ordering reasoning as the
      // vendor doc above.
      if (role == UserRole.driver) {
        final driver = Driver(id: uid, userId: uid, isAvailable: true);
        await _firestore.collection('drivers').doc(uid).set(driver.toMap());
      }

      await _firestore.collection('users').doc(uid).set(appUser.toMap());

      return appUser;
    });
  }

  Future<void> signOut() {
    return guardFuture(() async {
      final uid = _auth.currentUser?.uid;
      if (uid != null) {
        try {
          // Best-effort: clear the FCM token so a shared/reused device
          // doesn't keep receiving this user's notifications after sign-out.
          // Must happen before signOut() — firestore.rules' isSelf(userId)
          // check needs request.auth to still be non-null for this write.
          await _firestore.collection('users').doc(uid).update({'fcmToken': FieldValue.delete()});
        } catch (_) {
          // Never let notification-token cleanup block the actual sign-out.
        }
      }
      await _auth.signOut();
    });
  }

  Future<void> sendPasswordResetEmail(String email) {
    return guardFuture(() => _auth.sendPasswordResetEmail(email: email));
  }

  // Firestore doc deletion doesn't cascade to subcollections, so the saved
  // addresses under users/{uid}/addresses are cleared first — otherwise
  // they'd be orphaned, unreachable data left behind in the project.
  // `user.delete()` can throw 'requires-recent-login' (mapped in
  // AppException) if the session is old; the Firestore doc is deleted first
  // since that's the safer partial-failure state — a stray Auth account
  // with no profile doc already has a recovery path (AuthService.signIn's
  // `_ensureUserProfile` backfills a fresh customer profile on next sign-in),
  // whereas a stray profile doc with no Auth account would be permanently
  // unreachable (nothing could ever sign in as that uid again).
  Future<void> deleteAccount() {
    return guardFuture(() async {
      final user = _auth.currentUser;
      if (user == null) return;
      final uid = user.uid;

      final addresses = await _firestore.collection('users').doc(uid).collection('addresses').get();
      final batch = _firestore.batch();
      for (final doc in addresses.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(_firestore.collection('users').doc(uid));
      await batch.commit();

      await user.delete();
    });
  }
}
