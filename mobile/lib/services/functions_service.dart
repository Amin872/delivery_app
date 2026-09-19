import 'package:cloud_functions/cloud_functions.dart';

import '../core/errors/guard.dart';

/// Thin wrapper around callable Cloud Functions, mirroring the pattern used
/// by AuthService/FirestoreService (plain class, optional injected instance).
class FunctionsService {
  FunctionsService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  /// Calls the `acceptDelivery` callable, which atomically assigns the
  /// signed-in driver to [orderId] (see functions/src/orders.ts). Throws an
  /// [AppException] — most commonly `action-no-longer-available` if another
  /// driver already accepted the order first.
  Future<void> acceptDelivery(String orderId) {
    return guardFuture(() =>
        _functions.httpsCallable('acceptDelivery').call({'orderId': orderId}));
  }

  /// Calls the `advanceDelivery` callable, which atomically moves [orderId]
  /// to its next status (pickedUp -> delivering -> delivered) for the
  /// signed-in driver assigned to it (see functions/src/orders.ts). Throws
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
  /// readyForPickup or pickedUp — throws an [AppException]
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
