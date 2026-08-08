import 'package:flutter/material.dart';

/// Icon + semantic-color SnackBar, replacing every bare
/// `SnackBar(content: Text(...))` call in the app. Takes a [ColorScheme]
/// rather than a [BuildContext] so call sites with no local context at the
/// point a message arrives (e.g. `app.dart`'s foreground push-notification
/// handler, which shows a SnackBar via a `GlobalKey<ScaffoldMessengerState>`)
/// can build one too.
SnackBar buildAppSnackBar(ColorScheme colorScheme, String message, {bool isError = false}) {
  final backgroundColor = isError ? colorScheme.errorContainer : colorScheme.primaryContainer;
  final foregroundColor = isError ? colorScheme.onErrorContainer : colorScheme.onPrimaryContainer;
  return SnackBar(
    backgroundColor: backgroundColor,
    content: Row(
      children: [
        Icon(
          isError ? Icons.error_outline : Icons.check_circle_outline,
          color: foregroundColor,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(message, style: TextStyle(color: foregroundColor)),
        ),
      ],
    ),
  );
}
