import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/driver.dart';

void main() {
  Map<String, dynamic> baseDriver() => {
        'userId': 'driver-1',
        'isAvailable': true,
        'ratingSum': 0,
        'ratingCount': 0,
      };

  group('Driver.approvalStatus', () {
    test('parses a stored approvalStatus', () {
      for (final status in ApprovalStatus.values) {
        final driver = Driver.fromMap('driver-1', {...baseDriver(), 'approvalStatus': status.name});
        expect(driver.approvalStatus, status);
      }
    });

    test('reads a driver doc that predates the field as pending, without throwing', () {
      final driver = Driver.fromMap('driver-1', baseDriver());

      expect(driver.approvalStatus, ApprovalStatus.pending);
    });

    test('reads an explicit null approvalStatus as pending', () {
      final driver = Driver.fromMap('driver-1', {...baseDriver(), 'approvalStatus': null});

      expect(driver.approvalStatus, ApprovalStatus.pending);
    });

    test('reads an unrecognized approvalStatus as pending, never approved', () {
      final driver = Driver.fromMap('driver-1', {...baseDriver(), 'approvalStatus': 'superApproved'});

      expect(driver.approvalStatus, ApprovalStatus.pending);
    });

    test('defaults to pending when constructed without one', () {
      const driver = Driver(id: 'driver-1', userId: 'driver-1', isAvailable: true);

      expect(driver.approvalStatus, ApprovalStatus.pending);
    });

    test('toMap writes approvalStatus and round-trips it', () {
      const driver = Driver(
        id: 'driver-1',
        userId: 'driver-1',
        isAvailable: false,
        ratingSum: 9,
        ratingCount: 2,
        approvalStatus: ApprovalStatus.approved,
      );

      final map = driver.toMap();
      expect(map['approvalStatus'], 'approved');

      final restored = Driver.fromMap(driver.id, map);
      expect(restored.approvalStatus, ApprovalStatus.approved);
      expect(restored.isAvailable, isFalse);
      expect(restored.ratingSum, 9);
      expect(restored.ratingCount, 2);
    });
  });
}
