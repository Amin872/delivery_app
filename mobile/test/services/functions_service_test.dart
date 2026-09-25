import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/core/errors/app_exception.dart';
import 'package:delivery_app/services/functions_service.dart';

// FirebaseFunctions/HttpsCallable/HttpsCallableResult are plain (non-sealed)
// classes in cloud_functions 5.x, so they can be mocktail-mocked directly.
class MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class MockHttpsCallable extends Mock implements HttpsCallable {}

class MockHttpsCallableResult extends Mock implements HttpsCallableResult<Map<String, dynamic>> {}

void main() {
  late MockFirebaseFunctions functions;
  late MockHttpsCallable callable;
  late MockHttpsCallableResult result;
  late FunctionsService service;

  setUp(() {
    functions = MockFirebaseFunctions();
    callable = MockHttpsCallable();
    result = MockHttpsCallableResult();
    service = FunctionsService(functions: functions);
    when(() => functions.httpsCallable('createOrder')).thenReturn(callable);
  });

  group('createOrder', () {
    test('sends only vendorId, items[{menuItemId, quantity}] and addressId', () async {
      when(() => result.data).thenReturn({
        'orderId': 'order-1',
        'subtotal': 7000,
        'deliveryFee': 1500,
        'total': 8500,
      });
      when(() => callable.call<Map<String, dynamic>>(any())).thenAnswer((_) async => result);

      await service.createOrder(
        vendorId: 'vendor-1',
        items: const [
          (menuItemId: 'falafel', quantity: 2),
          (menuItemId: 'hummus', quantity: 1),
        ],
        addressId: 'address-1',
      );

      final payload =
          verify(() => callable.call<Map<String, dynamic>>(captureAny())).captured.single as Map;
      expect(payload, {
        'vendorId': 'vendor-1',
        'items': [
          {'menuItemId': 'falafel', 'quantity': 2},
          {'menuItemId': 'hummus', 'quantity': 1},
        ],
        'addressId': 'address-1',
      });
      // Nothing the server must decide is ever sent.
      for (final key in [
        'customerId',
        'total',
        'subtotal',
        'deliveryFee',
        'status',
        'driverId',
        'createdAt',
        'vendorName',
        'deliveryAddress',
      ]) {
        expect(payload.containsKey(key), isFalse, reason: key);
      }
      for (final line in payload['items'] as List) {
        expect((line as Map).keys, unorderedEquals(['menuItemId', 'quantity']));
      }
    });

    test('returns the server-calculated amounts, parsing ints as doubles', () async {
      when(() => result.data).thenReturn({
        'orderId': 'order-1',
        'subtotal': 7000,
        'deliveryFee': 0,
        'total': 7000.5,
      });
      when(() => callable.call<Map<String, dynamic>>(any())).thenAnswer((_) async => result);

      final placed = await service.createOrder(
        vendorId: 'vendor-1',
        items: const [(menuItemId: 'falafel', quantity: 2)],
        addressId: 'address-1',
      );

      expect(placed.orderId, 'order-1');
      expect(placed.subtotal, 7000.0);
      expect(placed.deliveryFee, 0.0);
      expect(placed.total, 7000.5);
    });

    test('surfaces the server reason code as the AppException code', () async {
      when(() => callable.call<Map<String, dynamic>>(any())).thenThrow(
        FirebaseFunctionsException(
          code: 'failed-precondition',
          message: 'Vendor is currently closed.',
          details: {'reason': 'vendor-closed'},
        ),
      );

      await expectLater(
        () => service.createOrder(
          vendorId: 'vendor-1',
          items: const [(menuItemId: 'falafel', quantity: 1)],
          addressId: 'address-1',
        ),
        throwsA(isA<AppException>().having((e) => e.code, 'code', 'vendor-closed')),
      );
    });
  });

  group('getOrderContact', () {
    setUp(() {
      when(() => functions.httpsCallable('getOrderContact')).thenReturn(callable);
    });

    test('sends only orderId and the target name, and returns the phone', () async {
      when(() => result.data).thenReturn({'phone': '+963 900 000 001'});
      when(() => callable.call<Map<String, dynamic>>(any())).thenAnswer((_) async => result);

      final phone = await service.getOrderContact('order-1', ContactTarget.driver);

      expect(phone, '+963 900 000 001');
      final payload =
          verify(() => callable.call<Map<String, dynamic>>(captureAny())).captured.single as Map;
      expect(payload, {'orderId': 'order-1', 'target': 'driver'});
    });

    for (final reason in ['phone-unavailable', 'contact-not-authorized']) {
      test('surfaces the server reason $reason as the AppException code', () async {
        when(() => callable.call<Map<String, dynamic>>(any())).thenThrow(
          FirebaseFunctionsException(code: 'failed-precondition', message: 'x', details: {'reason': reason}),
        );

        await expectLater(
          () => service.getOrderContact('order-1', ContactTarget.customer),
          throwsA(isA<AppException>().having((e) => e.code, 'code', reason)),
        );
      });
    }
  });
}
