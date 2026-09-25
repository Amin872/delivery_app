import 'package:cloud_functions/cloud_functions.dart';

import '../core/errors/guard.dart';

/// One cart line as sent to `createOrder` — only what the customer chose.
/// Name and price are deliberately absent: the server reads both from the
/// vendor's menu.
typedef OrderLineRequest = ({String menuItemId, int quantity});

/// What `createOrder` returns: the new order's id plus the amounts the
/// server actually charged, which are authoritative over any local cart
/// estimate.
class PlacedOrder {
  const PlacedOrder({
    required this.orderId,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
  });

  final String orderId;
  final double subtotal;
  final double deliveryFee;
  final double total;

  factory PlacedOrder.fromMap(Map<String, dynamic> map) {
    return PlacedOrder(
      orderId: map['orderId'] as String,
      subtotal: (map['subtotal'] as num).toDouble(),
      deliveryFee: (map['deliveryFee'] as num).toDouble(),
      total: (map['total'] as num).toDouble(),
    );
  }
}

/// Which participant of an order to ask `getOrderContact` for. The server
/// derives the actual account from the order — no uid is ever sent.
enum ContactTarget { customer, driver, vendor }

/// Thin wrapper around callable Cloud Functions, mirroring the pattern used
/// by AuthService/FirestoreService (plain class, optional injected instance).
class FunctionsService {
  FunctionsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Calls the `createOrder` callable — the only way to place an order
  /// (firestore.rules denies client-side creates). Sends just the vendor,
  /// the chosen items and quantities, and the id of one of the customer's
  /// own saved addresses; the server re-prices everything, adds the
  /// delivery fee, and writes the order (see functions/src/createOrder.ts).
  /// Throws an [AppException] whose code is the server's reason (e.g.
  /// `vendor-closed`, `minimum-order-not-met`) when it refuses the order.
  Future<PlacedOrder> createOrder({
    required String vendorId,
    required List<OrderLineRequest> items,
    required String addressId,
  }) {
    return guardFuture(() async {
      final result = await _functions.httpsCallable('createOrder').call<Map<String, dynamic>>({
        'vendorId': vendorId,
        'items': [
          for (final line in items) {'menuItemId': line.menuItemId, 'quantity': line.quantity},
        ],
        'addressId': addressId,
      });
      return PlacedOrder.fromMap(Map<String, dynamic>.from(result.data));
    });
  }

  /// Calls the `getOrderContact` callable (functions/src/contacts.ts) and
  /// returns the phone number of [target] on [orderId] — the only way one
  /// order participant can reach another's phone (users/{uid} stays private
  /// in firestore.rules). The server checks participation and status.
  /// Throws an [AppException] coded `contact-not-authorized` or
  /// `phone-unavailable` when it refuses.
  Future<String> getOrderContact(String orderId, ContactTarget target) {
    return guardFuture(() async {
      final result = await _functions.httpsCallable('getOrderContact').call<Map<String, dynamic>>({
        'orderId': orderId,
        'target': target.name,
      });
      return result.data['phone'] as String;
    });
  }

  /// Calls the `acceptDelivery` callable, which atomically assigns the
  /// signed-in driver to [orderId] (see functions/src/orders.ts). Throws an
  /// [AppException] — most commonly `action-no-longer-available` if another
  /// driver already accepted the order first.
  Future<void> acceptDelivery(String orderId) {
    return guardFuture(() =>
        _functions.httpsCallable('acceptDelivery').call({'orderId': orderId}));
  }

  /// Calls the `advanceDelivery` callable, which atomically moves [orderId]
  /// to its next status (driverAssigned -> pickedUp -> delivering ->
  /// delivered) for the signed-in driver assigned to it (see
  /// functions/src/orders.ts). Throws
  /// an [AppException] — `action-no-longer-available` if the order has no
  /// next step from its current status, `permission-denied` if the caller
  /// isn't the assigned driver. [proofImageUrl] (already uploaded to
  /// storage.rules' orderProofs/{orderId} path) is only persisted when this
  /// call lands the order on `delivered`.
  Future<void> advanceDelivery(String orderId, {String? proofImageUrl}) {
    return guardFuture(() => _functions.httpsCallable('advanceDelivery').call({
          'orderId': orderId,
          if (proofImageUrl != null) 'proofImageUrl': proofImageUrl,
        }));
  }

  /// Calls the `adminCancelOrder` callable, which force-cancels [orderId] on
  /// an admin's behalf (see functions/src/orders.ts). Only succeeds while
  /// the order is still pending/accepted/preparing/readyForPickup — throws
  /// an [AppException] `action-no-longer-available` once a driver has
  /// already picked it up, and `permission-denied` if the caller isn't an
  /// admin.
  Future<void> adminCancelOrder(String orderId) {
    return guardFuture(
        () => _functions.httpsCallable('adminCancelOrder').call({'orderId': orderId}));
  }

  /// Calls the `adminReassignDriver` callable, which atomically reassigns
  /// [orderId] to [driverId] on an admin's behalf (see
  /// functions/src/orders.ts). Only succeeds while the order is
  /// readyForPickup, driverAssigned, or pickedUp — throws an [AppException]
  /// `action-no-longer-available` once the order is delivering or later,
  /// and `not-found`/`permission-denied` if [driverId] isn't a real driver
  /// account.
  Future<void> adminReassignDriver(String orderId, String driverId) {
    return guardFuture(() => _functions.httpsCallable('adminReassignDriver').call({
          'orderId': orderId,
          'driverId': driverId,
        }));
  }
}
