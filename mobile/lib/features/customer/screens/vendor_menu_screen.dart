import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../providers/cart_provider.dart';
import 'cart_screen.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final vendorMenuProvider = StreamProvider.family<List<MenuItem>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchMenu(vendorId);
});

class VendorMenuScreen extends ConsumerWidget {
  const VendorMenuScreen({required this.vendor, super.key});

  final Vendor vendor;

  Future<void> _addToCart(BuildContext context, WidgetRef ref, MenuItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final added = ref.read(cartProvider.notifier).addItem(vendor.id, vendor.name, item);
    if (added) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.switchVendorConfirmTitle),
        content: Text(l10n.switchVendorConfirmMessage),
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
    if (confirmed == true) {
      ref.read(cartProvider.notifier).replaceWithItem(vendor.id, vendor.name, item);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(vendorMenuProvider(vendor.id));
    final cart = ref.watch(cartProvider);
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        leading: vendor.imageUrl == null
            ? null
            : Padding(
                padding: const EdgeInsets.all(8),
                child: CircleAvatar(backgroundImage: NetworkImage(vendor.imageUrl!)),
              ),
        title: Text(vendor.name),
        actions: const [LanguageToggleButton()],
      ),
      body: menuAsync.when(
        data: (items) {
          final available = items.where((item) => item.available).toList();
          if (available.isEmpty) {
            return Center(child: Text(l10n.vendorMenuEmptyMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: available.length,
            itemBuilder: (context, index) {
              final item = available[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        item.imageUrl != null ? NetworkImage(item.imageUrl!) : null,
                    child: item.imageUrl == null ? const Icon(Icons.fastfood_outlined) : null,
                  ),
                  title: Text(item.name),
                  subtitle: Text(currencyFormat.format(item.price)),
                  trailing: IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    tooltip: l10n.addToCartTooltip,
                    onPressed: () => _addToCart(context, ref, item),
                  ),
                ),
              ).staggeredEntrance(index);
            },
          );
        },
        loading: () => const ListSkeletonLoader(),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: GradientButton(
                  onPressed: () => Navigator.of(context)
                      .push(MaterialPageRoute(builder: (_) => const CartScreen())),
                  child: Text(
                    '${l10n.viewCartButton} · ${cart.itemCount} · ${currencyFormat.format(cart.total)}',
                  ),
                ),
              ),
            ),
    );
  }
}
