import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Wraps [AsyncValue.when]'s result in an [AnimatedSwitcher], cross-fading
/// between loading/data/error states. The real branch selection is
/// delegated straight to [when] (so behavior — including Riverpod's
/// skip-loading-on-refresh nuances — is unchanged); this only adds a
/// transition keyed on the state's *kind*, not its data, so a live stream
/// emitting new data in the same "data" state doesn't replay the fade.
extension AnimatedAsyncValue<T> on AsyncValue<T> {
  Widget animatedWhen({
    required Widget Function(T data) data,
    required Widget Function() loading,
    required Widget Function(Object error, StackTrace stackTrace) error,
  }) {
    final child = when(data: data, loading: loading, error: error);
    final stateKey = isLoading
        ? 'loading'
        : hasError
            ? 'error'
            : 'data';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(stateKey), child: child),
    );
  }
}
