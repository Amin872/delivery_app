// Basic model round-trip tests. Widget tests that build DeliveryApp require
// Firebase.initializeApp(), which needs the Firebase emulator suite or a
// configured project — see integration_test/ for those instead.

import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/app_user.dart';

void main() {
  test('AppUser round-trips through toMap/fromMap', () {
    const user = AppUser(
      id: 'user-1',
      email: 'driver@example.com',
      displayName: 'Alex Driver',
      role: UserRole.driver,
      phoneNumber: '+15551234567',
    );

    final restored = AppUser.fromMap(user.id, user.toMap());

    expect(restored.id, user.id);
    expect(restored.email, user.email);
    expect(restored.displayName, user.displayName);
    expect(restored.role, user.role);
    expect(restored.phoneNumber, user.phoneNumber);
  });
}
