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

  Future<AppUser?> fetchAppUser(String uid) => guardFuture(() async {
        final doc = await _firestore.collection('users').doc(uid).get();
        if (!doc.exists) return null;
        return AppUser.fromMap(doc.id, doc.data()!);
      });

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return guardFuture(() => _auth.signInWithEmailAndPassword(
          email: email,
          password: password,
        ));
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
}
