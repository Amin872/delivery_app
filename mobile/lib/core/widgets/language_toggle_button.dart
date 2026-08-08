import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/preferences_provider.dart';

/// AppBar action that flips between Arabic and English, persisted via
/// [localeProvider]. Shown pre-login too, so a user isn't stuck reading a
/// language they can't follow before they even reach the role-gated home.
class LanguageToggleButton extends ConsumerWidget {
  const LanguageToggleButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return IconButton(
      icon: const Icon(Icons.translate),
      tooltip: AppLocalizations.of(context)!.languageToggleTooltip,
      onPressed: () => ref.read(localeProvider.notifier).toggle(),
    );
  }
}
