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

    final vendorDoc = await firestore.collection('vendors').doc('driver-uid').get();
    expect(vendorDoc.exists, isFalse);
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
}
