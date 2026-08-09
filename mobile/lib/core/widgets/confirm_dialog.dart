import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// Shared Cancel/Confirm dialog — replaces the near-identical `AlertDialog`
/// block that was copy-pasted across order-cancel, cart-switch, and
/// menu-item-delete confirmations. Resolves `true` only if Confirm was
/// tapped, `false` for Cancel, `null` if dismissed.
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String message,
  String? title,
}) {
  final l10n = AppLocalizations.of(context)!;
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
          onPressed: () => Navigator.pop(context, true),
          child: Text(l10n.confirmButton),
        ),
      ],
    ),
  );
}
