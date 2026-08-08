import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/review.dart';
import '../../../models/vendor.dart';
import '../providers/cart_provider.dart';
import 'cart_screen.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final vendorMenuProvider = StreamProvider.family<List<MenuItem>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchMenu(vendorId);
});

final vendorReviewsProvider = StreamProvider.family<List<Review>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorReviews(vendorId);
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
          final reviewsAsync = ref.watch(vendorReviewsProvider(vendor.id));
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: vendor.ratingCount == 0
                    ? Text(l10n.notRatedYetLabel, style: Theme.of(context).textTheme.bodySmall)
                    : StarRatingDisplay(rating: vendor.averageRating, count: vendor.ratingCount),
              ),
              if (available.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(l10n.vendorMenuEmptyMessage),
                )
              else
                for (var index = 0; index < available.length; index++)
                  Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundImage: available[index].imageUrl != null
                            ? NetworkImage(available[index].imageUrl!)
                            : null,
                        child: available[index].imageUrl == null
                            ? const Icon(Icons.fastfood_outlined)
                            : null,
                      ),
                      title: Text(available[index].name),
                      subtitle: Text(currencyFormat.format(available[index].price)),
                      trailing: IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        tooltip: l10n.addToCartTooltip,
                        onPressed: () => _addToCart(context, ref, available[index]),
                      ),
                    ),
                  ).staggeredEntrance(index),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(l10n.reviewsTitle, style: Theme.of(context).textTheme.titleMedium),
              ),
              reviewsAsync.when(
                data: (reviews) => reviews.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(l10n.noReviewsMessage),
                      )
                    : Column(
                        children: [
                          for (final review in reviews)
                            ListTile(
                              title: StarRatingDisplay(rating: review.vendorRating.toDouble(), size: 14),
                              subtitle: review.comment == null ? null : Text(review.comment!),
                            ),
                        ],
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),
            ],
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
