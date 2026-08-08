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
  /// isn't the assigned driver.
  Future<void> advanceDelivery(String orderId) {
    return guardFuture(() =>
        _functions.httpsCallable('advanceDelivery').call({'orderId': orderId}));
  }
}
