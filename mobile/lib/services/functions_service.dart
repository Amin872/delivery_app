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
}
