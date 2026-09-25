import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/services/auth_service.dart';

// FirebaseAuth (unlike Query/DocumentReference, which cloud_firestore 5.x
// marks sealed) is a plain abstract class, so it's fine to mocktail-mock.
class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockUser extends Mock implements User {}

void main() {
  test(
      'signIn maps a FirebaseAuthException to AppException(invalid-credential)',
      () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenThrow(FirebaseAuthException(code: 'invalid-credential'));

    final service = AuthService(auth: auth, firestore: firestore);

    await expectLater(
      () => service.signIn(email: 'a@b.com', password: 'wrong'),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', 'invalid-credential'),
      ),
    );
  });

  test('signUp creates a drivers/{uid} doc when role is driver', () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final credential = MockUserCredential();
    final user = MockUser();

    when(() => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('driver-uid');

    final service = AuthService(auth: auth, firestore: firestore);

    await service.signUp(
      email: 'driver@example.com',
      password: 'password123',
      displayName: 'Driver One',
      role: UserRole.driver,
      phoneNumber: '+15551234567',
    );

    final driverDoc = await firestore.collection('drivers').doc('driver-uid').get();
    expect(driverDoc.exists, isTrue);
    expect(driverDoc.data()!['userId'], 'driver-uid');
    expect(driverDoc.data()!['isAvailable'], isTrue);
    // firestore.rules' drivers create rule requires exactly 'pending'.
    expect(driverDoc.data()!['approvalStatus'], 'pending');
    expect(driverDoc.data()!['ratingSum'], 0);
    expect(driverDoc.data()!['ratingCount'], 0);

    final vendorDoc = await firestore.collection('vendors').doc('driver-uid').get();
    expect(vendorDoc.exists, isFalse);
  });

  test('signUp creates a pending vendors/{uid} doc with empty pickup fields when role is vendor',
      () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final credential = MockUserCredential();
    final user = MockUser();

    when(() => auth.createUserWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('vendor-uid');

    final service = AuthService(auth: auth, firestore: firestore);

    await service.signUp(
      email: 'vendor@example.com',
      password: 'password123',
      displayName: 'Vendor One',
      role: UserRole.vendor,
      phoneNumber: '+15551234567',
    );

    final vendorDoc = await firestore.collection('vendors').doc('vendor-uid').get();
    expect(vendorDoc.exists, isTrue);
    final data = vendorDoc.data()!;
    expect(data['ownerId'], 'vendor-uid');
    expect(data['approvalStatus'], 'pending');
    // Present but unset — no fabricated address or coordinate.
    expect(data.containsKey('pickupAddress'), isTrue);
    expect(data['pickupAddress'], isNull);
    expect(data['pickupLatitude'], isNull);
    expect(data['pickupLongitude'], isNull);

    final driverDoc = await firestore.collection('drivers').doc('vendor-uid').get();
    expect(driverDoc.exists, isFalse);
  });

  test('signIn creates a default customer profile when users/{uid} is missing', () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final credential = MockUserCredential();
    final user = MockUser();

    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('legacy-uid');

    final service = AuthService(auth: auth, firestore: firestore);
    await service.signIn(email: 'legacy@example.com', password: 'password123');

    final userDoc = await firestore.collection('users').doc('legacy-uid').get();
    expect(userDoc.exists, isTrue);
    expect(userDoc.data()!['role'], 'customer');
    expect(userDoc.data()!['email'], 'legacy@example.com');
  });

  test('signIn leaves an existing users/{uid} profile untouched', () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final credential = MockUserCredential();
    final user = MockUser();

    when(() => auth.signInWithEmailAndPassword(
          email: any(named: 'email'),
          password: any(named: 'password'),
        )).thenAnswer((_) async => credential);
    when(() => credential.user).thenReturn(user);
    when(() => user.uid).thenReturn('vendor-uid');
    await firestore.collection('users').doc('vendor-uid').set({
      'email': 'vendor@example.com',
      'displayName': 'Vendor One',
      'role': 'vendor',
    });

    final service = AuthService(auth: auth, firestore: firestore);
    await service.signIn(email: 'vendor@example.com', password: 'password123');

    final userDoc = await firestore.collection('users').doc('vendor-uid').get();
    expect(userDoc.data()!['role'], 'vendor');
    expect(userDoc.data()!['displayName'], 'Vendor One');
  });

  test('signOut clears fcmToken before calling through to FirebaseAuth.signOut', () async {
    final auth = MockFirebaseAuth();
    final firestore = FakeFirebaseFirestore();
    final user = MockUser();

    when(() => user.uid).thenReturn('user-1');
    when(() => auth.currentUser).thenReturn(user);
    when(() => auth.signOut()).thenAnswer((_) async {});
    await firestore.collection('users').doc('user-1').set({
      'email': 'a@b.com',
      'displayName': 'A',
      'role': 'customer',
      'fcmToken': 'stale-token',
    });

    final service = AuthService(auth: auth, firestore: firestore);
    await service.signOut();

    final doc = await firestore.collection('users').doc('user-1').get();
    expect(doc.data()!.containsKey('fcmToken'), isFalse);
    verify(() => auth.signOut()).called(1);
  });

  // Phase 31 (M1): deleteAccount deletes only the Firebase Auth account;
  // users/{uid} and its addresses are removed server-side by the
  // onAuthUserDeleted Cloud Function (firestore.rules forbid client deletes).
  group('deleteAccount (Phase 31 M1)', () {
    Future<FakeFirebaseFirestore> seededFirestore() async {
      final firestore = FakeFirebaseFirestore();
      await firestore.collection('users').doc('user-1').set({'email': 'a@b.com', 'role': 'customer'});
      await firestore.collection('users').doc('user-1').collection('addresses').doc('home').set({'addressText': 'Mezzeh'});
      await firestore.collection('users').doc('user-1').collection('addresses').doc('work').set({'addressText': 'Malki'});
      return firestore;
    }

    Future<void> expectProfileUntouched(FakeFirebaseFirestore firestore) async {
      expect((await firestore.collection('users').doc('user-1').get()).exists, isTrue);
      final addresses = await firestore.collection('users').doc('user-1').collection('addresses').get();
      expect(addresses.docs.map((d) => d.id), unorderedEquals(['home', 'work']));
    }

    test('deletes the Auth account and nothing in Firestore from the client', () async {
      final auth = MockFirebaseAuth();
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('user-1');
      when(() => user.delete()).thenAnswer((_) async {});
      final firestore = await seededFirestore();

      await AuthService(auth: auth, firestore: firestore).deleteAccount();

      verify(() => user.delete()).called(1);
      await expectProfileUntouched(firestore);
    });

    test('requires-recent-login: surfaces the mapped error and deletes nothing', () async {
      final auth = MockFirebaseAuth();
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('user-1');
      when(() => user.delete()).thenThrow(FirebaseAuthException(code: 'requires-recent-login'));
      final firestore = await seededFirestore();

      await expectLater(
        () => AuthService(auth: auth, firestore: firestore).deleteAccount(),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'requires-recent-login')),
      );
      await expectProfileUntouched(firestore);
    });

    test('any other Auth failure also leaves Firestore untouched', () async {
      final auth = MockFirebaseAuth();
      final user = MockUser();
      when(() => auth.currentUser).thenReturn(user);
      when(() => user.uid).thenReturn('user-1');
      when(() => user.delete()).thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      final firestore = await seededFirestore();

      await expectLater(() => AuthService(auth: auth, firestore: firestore).deleteAccount(), throwsA(isA<AppException>()));
      await expectProfileUntouched(firestore);
    });

    test('does nothing when no one is signed in', () async {
      final auth = MockFirebaseAuth();
      when(() => auth.currentUser).thenReturn(null);
      final firestore = await seededFirestore();

      await AuthService(auth: auth, firestore: firestore).deleteAccount();

      await expectProfileUntouched(firestore);
    });
  });
}
