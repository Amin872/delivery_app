import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../providers/cart_provider.dart';

/// Add button ↔ quantity stepper for a single [MenuItem], reading/writing
/// the existing `cartProvider` directly — the one place this control's
/// look/logic lives, so `MenuItemCard` (vertical menu rows) and
/// `MostOrderedCard` (horizontal "most ordered" carousel) can't drift out
/// of sync with each other or with the cart's real state. [onAdd] is only
/// invoked for the initial add (quantity 0 → 1); once the item is in the
/// cart, +/- write straight to [cartProvider] the same way the old inline
/// version in `MenuItemCard` did.
class CartQuantityControl extends ConsumerWidget {
  const CartQuantityControl({
    required this.item,
    required this.onAdd,
    this.direction = Axis.vertical,
    this.addButtonBuilder,
    super.key,
  });

  final MenuItem item;
  final VoidCallback onAdd;

  /// `Axis.vertical` (add icon above count above remove icon) matches
  /// `MenuItemCard`'s original row layout, where the control sits in a
  /// narrow trailing column. `Axis.horizontal` (remove — count — add in a
  /// line) suits `MostOrderedCard`'s compact carousel tile, where a fixed
  /// card height leaves no room for a tall stacked control.
  final Axis direction;

  /// Overrides just the zero-quantity ("add") visual — e.g. `MostOrderedCard`'s
  /// corner-flag badge, which looks nothing like the plain circular icon
  /// used elsewhere — while every cart read/write stays here, in the one
  /// place this control's logic lives. Receives the tap callback already
  /// resolved to `null` when [MenuItem.available] is false, so the builder
  /// never needs to check availability itself.
  final Widget Function(VoidCallback? onTap)? addButtonBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final quantity = ref.watch(cartProvider).lines[item.id]?.quantity ?? 0;

    if (quantity == 0) {
      final onTap = item.available ? onAdd : null;
      if (addButtonBuilder != null) return addButtonBuilder!(onTap);
      return IconButton(
        icon: Icon(Icons.add_circle, color: colorScheme.primary, size: 32),
        tooltip: l10n.addToCartTooltip,
        onPressed: onTap,
        // Horizontal layout (MostOrderedCard's compact tile) has no room for
        // IconButton's default 48x48 tap target next to the price — spelled
        // out explicitly (`EdgeInsets.all(8)`, IconButton's own default)
        // rather than omitted, since vertical must still get that default
        // at the same call site.
        padding: direction == Axis.horizontal ? EdgeInsets.zero : const EdgeInsets.all(8),
        constraints: direction == Axis.horizontal ? const BoxConstraints() : null,
      );
    }

    void increment() {
      HapticFeedback.selectionClick();
      ref.read(cartProvider.notifier).setQuantity(item.id, quantity + 1);
    }

    void decrement() {
      HapticFeedback.selectionClick();
      ref.read(cartProvider.notifier).setQuantity(item.id, quantity - 1);
    }

    final compact = direction == Axis.horizontal;
    final removeButton = IconButton(
      icon: const Icon(Icons.remove_circle_outline),
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: compact ? const BoxConstraints() : null,
      onPressed: decrement,
    );
    final addButton = IconButton(
      icon: const Icon(Icons.add_circle_outline),
      padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
      constraints: compact ? const BoxConstraints() : null,
      onPressed: increment,
    );
    final countLabel = Text('$quantity', style: textTheme.labelLarge);

    return direction == Axis.vertical
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [addButton, countLabel, removeButton],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              removeButton,
              const SizedBox(width: 4),
              countLabel,
              const SizedBox(width: 4),
              addButton,
            ],
          );
  }
}
