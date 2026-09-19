import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/features/admin/screens/admin_drivers_screen.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/driver.dart';

AppUser _user(String id, UserRole role, {String name = 'Name', String email = 'a@b.com'}) {
  return AppUser(id: id, email: email, displayName: name, role: role);
}

Driver _driver(String id, {bool isAvailable = true, num ratingSum = 0, int ratingCount = 0}) {
  return Driver(id: id, userId: id, isAvailable: isAvailable, ratingSum: ratingSum, ratingCount: ratingCount);
}

void main() {
  test('buildDriverRows joins drivers with matching driver-role users', () {
    final rows = buildDriverRows(
      [_driver('driver-1', isAvailable: true), _driver('driver-2', isAvailable: false)],
      [
        _user('driver-1', UserRole.driver, name: 'Sam Driver'),
        _user('driver-2', UserRole.driver, name: 'Alex Driver'),
      ],
    );

    expect(rows.length, 2);
    expect(rows.map((r) => r.driverId), containsAll(['driver-1', 'driver-2']));
    expect(rows.firstWhere((r) => r.driverId == 'driver-1').isAvailable, isTrue);
    expect(rows.firstWhere((r) => r.driverId == 'driver-2').isAvailable, isFalse);
  });

  test('buildDriverRows excludes a driver doc with no matching driver-role user', () {
    final rows = buildDriverRows(
      [_driver('driver-1'), _driver('orphan-driver')],
      [_user('driver-1', UserRole.driver)],
    );

    expect(rows.length, 1);
    expect(rows.single.driverId, 'driver-1');
  });

  test('buildDriverRows excludes a user with role driver but no drivers/{uid} doc', () {
    final rows = buildDriverRows(
      [_driver('driver-1')],
      [_user('driver-1', UserRole.driver), _user('driver-2', UserRole.driver)],
    );

    expect(rows.length, 1);
    expect(rows.single.driverId, 'driver-1');
  });

  test('buildDriverRows excludes non-driver users even if a matching drivers doc exists', () {
    final rows = buildDriverRows(
      [_driver('user-1')],
      [_user('user-1', UserRole.customer)],
    );

    expect(rows, isEmpty);
  });

  test('buildDriverRows carries rating fields through unchanged', () {
    final rows = buildDriverRows(
      [_driver('driver-1', ratingSum: 12, ratingCount: 3)],
      [_user('driver-1', UserRole.driver)],
    );

    expect(rows.single.averageRating, 4.0);
    expect(rows.single.ratingCount, 3);
  });
}
