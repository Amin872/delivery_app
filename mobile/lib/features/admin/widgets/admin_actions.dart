import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../l10n/app_localizations.dart';

/// The one failure/success path for admin writes: runs [write], and only
/// once it has actually succeeded shows [successMessage] (if any). A failed
/// write shows a localized error snackbar (never the raw exception) and
/// returns false, so callers can roll back any optimistic UI. The messenger
/// is captured up front, so feedback still shows when the calling widget
/// (a bottom sheet, a list row) is gone by the time the write settles.
Future<bool> runAdminWrite(
  BuildContext context,
  Future<void> Function() write, {
  String? successMessage,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final colorScheme = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  try {
    await write();
  } catch (error) {
    var message = l10n.genericErrorMessage;
    if (context.mounted) message = localizedErrorMessage(context, error);
    messenger.showSnackBar(buildAppSnackBar(colorScheme, message, isError: true));
    return false;
  }
  if (successMessage != null) {
    messenger.showSnackBar(buildAppSnackBar(colorScheme, successMessage));
  }
  return true;
}

/// A [Switch] bound to server state ([value], from a Firestore stream) whose
/// [onChanged] is an async write that resolves to whether it went through
/// (false on failure, or when the admin backed out of a confirmation).
/// While the write is in flight the switch shows the requested position and
/// is disabled, so it can't be toggled twice; afterwards it shows [value]
/// again — the new state once the write lands, or the old one (a rollback)
/// if it didn't.
class AdminAsyncSwitch extends StatefulWidget {
  const AdminAsyncSwitch({
    required this.value,
    required this.onChanged,
    required this.tooltip,
    super.key,
  });

  final bool value;
  final Future<bool> Function(bool value) onChanged;
  final String tooltip;

  @override
  State<AdminAsyncSwitch> createState() => _AdminAsyncSwitchState();
}

class _AdminAsyncSwitchState extends State<AdminAsyncSwitch> {
  bool? _pending;

  Future<void> _toggle(bool value) async {
    setState(() => _pending = value);
    try {
      await widget.onChanged(value);
    } finally {
      if (mounted) setState(() => _pending = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: Switch(
        value: _pending ?? widget.value,
        onChanged: _pending == null ? _toggle : null,
      ),
    );
  }
}

/// Icon + label row for an admin overflow-menu ([PopupMenuButton]) item —
/// same shape as the vendor menu screen's item actions. [color] tints a
/// destructive entry (e.g. reject, delete).
class AdminMenuItemLabel extends StatelessWidget {
  const AdminMenuItemLabel({required this.icon, required this.label, this.color, super.key});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconLarge, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: TextStyle(color: color))),
      ],
    );
  }
}

/// Horizontally scrolling row of filter chips. Its height follows the
/// chips themselves (so a larger text scale grows the row instead of
/// clipping it), and the gap after each chip is on its reading-order end,
/// so the row reads correctly in Arabic (RTL) and English (LTR).
class AdminFilterChipBar extends StatelessWidget {
  const AdminFilterChipBar({required this.chips, super.key});

  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final chip in chips)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: chip,
            ),
        ],
      ),
    );
  }
}

/// Search box for the server-searched admin lists. [onChanged] receives the
/// trimmed text only after typing pauses for [debounce], so a query isn't
/// sent per keystroke; the clear button resets the search immediately.
/// [helperText] states the matching rule (these searches match the start
/// of a field, not any part of it).
class AdminSearchField extends StatefulWidget {
  const AdminSearchField({
    required this.hintText,
    required this.onChanged,
    this.helperText,
    super.key,
  });

  static const debounce = Duration(milliseconds: 350);

  final String hintText;
  final String? helperText;
  final ValueChanged<String> onChanged;

  @override
  State<AdminSearchField> createState() => _AdminSearchFieldState();
}

class _AdminSearchFieldState extends State<AdminSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  void _onChanged(String value) {
    setState(() {}); // shows/hides the clear button
    _debounce?.cancel();
    _debounce = Timer(AdminSearchField.debounce, () => widget.onChanged(value.trim()));
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return TextField(
      controller: _controller,
      style: const TextStyle(color: VendorPalette.textPrimary),
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: const TextStyle(color: VendorPalette.textMuted),
        helperText: widget.helperText,
        helperMaxLines: 2,
        prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.clearSearchTooltip,
                onPressed: _clear,
              ),
        filled: true,
        fillColor: VendorPalette.surfaceContainer,
        border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
      ),
      onChanged: _onChanged,
    );
  }
}
