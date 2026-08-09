import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../../services/firestore_service.dart';
import '../../auth/providers/auth_provider.dart';
import 'my_orders_screen.dart';
import 'vendor_menu_screen.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

final openVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchOpenVendors();
});

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(openVendorsProvider);
    final l10n = AppLocalizations.of(context)!;
    final customerId = ref.watch(currentAppUserProvider).valueOrNull?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.nearbyVendorsTitle),
        actions: [
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: l10n.myOrdersTitle,
            onPressed: customerId == null
                ? null
                : () => Navigator.of(context)
                    .push(fadeSlideRoute(MyOrdersScreen(customerId: customerId))),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: vendorsAsync.animatedWhen(
          data: (vendors) {
          if (vendors.isEmpty) {
            return Center(child: Text(l10n.noOpenVendorsMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: vendors.length,
            itemBuilder: (context, index) {
              final vendor = vendors[index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage:
                        vendor.imageUrl != null ? NetworkImage(vendor.imageUrl!) : null,
                    child: vendor.imageUrl == null ? const Icon(Icons.storefront_outlined) : null,
                  ),
                  title: Text(vendor.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(vendor.description),
                      const SizedBox(height: 2),
                      vendor.ratingCount == 0
                          ? Text(l10n.notRatedYetLabel, style: Theme.of(context).textTheme.bodySmall)
                          : StarRatingDisplay(rating: vendor.averageRating, count: vendor.ratingCount),
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(fadeSlideRoute(VendorMenuScreen(vendor: vendor))),
                ),
              ).staggeredEntrance(index);
            },
          );
        },
        loading: () => const ListSkeletonLoader(),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
        ),
      ),
    );
  }
}
