import 'dart:async';

import 'app_exception.dart';

/// Runs [action], rethrowing any error as an [AppException] so callers
/// never see a raw Firebase exception.
Future<T> guardFuture<T>(Future<T> Function() action) async {
  try {
    return await action();
  } catch (error) {
    throw AppException.fromError(error);
  }
}

/// Wraps [source], replacing any stream error with an [AppException].
Stream<T> guardStream<T>(Stream<T> source) {
  final controller = StreamController<T>();
  final subscription = source.listen(
    controller.add,
    onError: (Object error, StackTrace stackTrace) {
      controller.addError(AppException.fromError(error), stackTrace);
    },
    onDone: controller.close,
  );
  controller.onCancel = subscription.cancel;
  return controller.stream;
}
