import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/errors/app_exception.dart';

FirebaseFunctionsException _functionsError(String code, {Object? details}) =>
    FirebaseFunctionsException(code: code, message: 'server message', details: details);

void main() {
  group('AppException.fromError for callable errors', () {
    test('uses every known createOrder reason as the code', () {
      for (final reason in AppException.orderReasons) {
        final error = _functionsError('failed-precondition', details: {'reason': reason});
        expect(AppException.fromError(error).code, reason);
      }
    });

    test('does not collapse createOrder failures into action-no-longer-available', () {
      final error = _functionsError(
        'failed-precondition',
        details: {'reason': 'minimum-order-not-met', 'minimumOrderAmount': 5000, 'subtotal': 4000},
      );
      expect(AppException.fromError(error).code, 'minimum-order-not-met');
    });

    test('an unknown reason falls back to the code-level mapping', () {
      final error = _functionsError('failed-precondition', details: {'reason': 'something-new'});
      expect(AppException.fromError(error).code, 'action-no-longer-available');
    });

    test('errors without details keep the existing code-level mapping', () {
      expect(AppException.fromError(_functionsError('failed-precondition')).code,
          'action-no-longer-available');
      expect(AppException.fromError(_functionsError('permission-denied')).code, 'permission-denied');
      expect(AppException.fromError(_functionsError('not-found')).code, 'not-found');
      expect(AppException.fromError(_functionsError('unavailable')).code, 'network-error');
    });

    test('non-map details are ignored', () {
      final error = _functionsError('not-found', details: 'vendor-closed');
      expect(AppException.fromError(error).code, 'not-found');
    });
  });
}
