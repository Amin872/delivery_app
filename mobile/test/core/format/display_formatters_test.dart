import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/format/display_formatters.dart';

void main() {
  group('shortOrderId', () {
    test('takes the last six letters/digits, upper-cased, with #', () {
      expect(shortOrderId('Xk3pQ9aB7cD2eF1gH4iJ'), '#1GH4IJ');
    });
    test('ignores separators in non-Firestore ids', () {
      expect(shortOrderId('local-order-ready'), '#RREADY');
    });
    test('short ids are kept whole', () {
      expect(shortOrderId('ab1'), '#AB1');
    });
    test('displayOrderId is the same text, LTR-isolated', () {
      final display = displayOrderId('local-order-ready');
      expect(display, isNot('#RREADY'));
      expect(stripBidiIsolates(display), '#RREADY');
    });
  });

  test('formatCoordinates: fixed digits, hemispheres, isolated', () {
    expect(stripBidiIsolates(formatCoordinates(33.5138, 36.2765)), '33.51380° N, 36.27650° E');
    expect(stripBidiIsolates(formatCoordinates(-12.5, -0.25, digits: 2)), '12.50° S, 0.25° W');
  });

  group('formatPhone', () {
    test('groups Syrian international numbers', () {
      expect(stripBidiIsolates(formatPhone('+963944123456')), '+963 944 123 456');
      expect(stripBidiIsolates(formatPhone('00963 944-123-456')), '+963 944 123 456');
    });
    test('groups Syrian national numbers', () {
      expect(stripBidiIsolates(formatPhone('0944123456')), '0944 123 456');
    });
    test('leaves anything else as typed (trimmed)', () {
      expect(stripBidiIsolates(formatPhone(' +44 20 7946 0958 ')), '+44 20 7946 0958');
    });
    test('is always LTR-isolated', () {
      expect(formatPhone('+963944123456').startsWith('\u2066'), isTrue);
    });
  });

  test('formatAmountForInput drops .00 but keeps real fractions', () {
    expect(formatAmountForInput(25000.0), '25000');
    expect(formatAmountForInput(12.5), '12.5');
    expect(formatAmountForInput(null), '');
  });
}
