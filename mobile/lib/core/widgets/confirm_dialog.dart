import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shared Cancel/Confirm dialog — replaces the near-identical `AlertDialog`
/// block that was copy-pasted across order-cancel, cart-switch, and
/// menu-item-delete confirmations. Resolves `true` only if Confirm was
/// tapped, `false` for Cancel, `null` if dismissed.
///
/// [isDestructive] recolors the Confirm button to `colorScheme.error` for
/// irreversible actions (e.g. delete account) — the dialog shape and
/// Cancel/Confirm semantics stay identical, so every existing call site is
/// unaffected by this optional flag.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String message,
  String? title,
  bool isDestructive = false,
}) {
  final l10n = AppLocalizations.of(context)!;
  final colorScheme = Theme.of(context).colorScheme;
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: title == null ? null : Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          style: isDestructive
              ? FilledButton.styleFrom(
                  backgroundColor: colorScheme.error, foregroundColor: colorScheme.onError)
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.confirmButton),
        ),
      ],
    ),
  );
}
