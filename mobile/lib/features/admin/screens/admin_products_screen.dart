import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';
import '../../../core/widgets/state_views.dart';

final allMenuItemsProvider = StreamProvider.autoDispose<List<MenuItem>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllMenuItems();
});

final allVendorsProvider = StreamProvider.autoDispose<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllVendors();
});

class ProductRow {
  const ProductRow({
    required this.itemId,
    required this.vendorId,
    required this.name,
    required this.price,
    required this.imageUrl,
    required this.available,
    required this.vendorName,
  });

  final String itemId;
  final String vendorId;
  final String name;
  final double price;
  final String? imageUrl;
  final bool available;
  final String vendorName;
}

/// Joins every product (`FirestoreService.watchAllMenuItems()` — the same
/// collection-group query CustomerHomeScreen's feed already uses, zero new
/// reads) with its vendor's name (`watchAllVendors()`, already used by
/// AdminVendorsScreen). Pure/Firebase-free so the join is unit-testable
/// independent of both streams — same reasoning as Drivers'
/// `buildDriverRows`. A product whose vendor doc is missing is still shown
/// (vendor deletion isn't possible today — `vendors.delete` is `if false`
/// in firestore.rules — but this stays defensive rather than silently
/// dropping a real product) with an empty vendor name.
List<ProductRow> buildProductRows(List<MenuItem> items, List<Vendor> vendors) {
  final vendorNamesById = {for (final vendor in vendors) vendor.id: vendor.name};
  return items
      .map((item) => ProductRow(
            itemId: item.id,
            vendorId: item.vendorId,
            name: item.name,
            price: item.price,
            imageUrl: item.imageUrl,
            available: item.available,
            vendorName: vendorNamesById[item.vendorId] ?? '',
          ))
      .toList();
}

enum _AvailabilityFilter { all, available, unavailable }

/// Read-only admin product browser across every vendor — no edit/delete/
/// delist here (Phase 4 Products is read-only; `menuItems` write rules are
/// unchanged), just visibility the admin panel didn't have before.
class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  String _query = '';
  _AvailabilityFilter _filter = _AvailabilityFilter.all;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AdminScaffold(
      title: l10n.adminNavProducts,
      selected: AdminDestination.products,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.searchProductsHint,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              filled: true,
              fillColor: VendorPalette.surfaceContainer,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _FilterChip(
                  label: l10n.allStatusesLabel,
                  selected: _filter == _AvailabilityFilter.all,
                  onSelected: () => setState(() => _filter = _AvailabilityFilter.all),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: l10n.availableLabel,
                  selected: _filter == _AvailabilityFilter.available,
                  onSelected: () => setState(() => _filter = _AvailabilityFilter.available),
                ),
                const SizedBox(width: AppSpacing.sm),
                _FilterChip(
                  label: l10n.unavailableLabel,
                  selected: _filter == _AvailabilityFilter.unavailable,
                  onSelected: () => setState(() => _filter = _AvailabilityFilter.unavailable),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(child: _ProductList(query: _query, filter: _filter)),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onSelected});

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _ProductList extends ConsumerWidget {
  const _ProductList({required this.query, required this.filter});

  final String query;
  final _AvailabilityFilter filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final itemsAsync = ref.watch(allMenuItemsProvider);
    final vendorsAsync = ref.watch(allVendorsProvider);

    if (itemsAsync.isLoading || vendorsAsync.isLoading) {
      return const ListSkeletonLoader();
    }
    if (itemsAsync.hasError) {
      return ErrorState(error: itemsAsync.error!);
    }
    if (vendorsAsync.hasError) {
      return ErrorState(error: vendorsAsync.error!);
    }

    var rows = buildProductRows(itemsAsync.value!, vendorsAsync.value!);

    if (query.isNotEmpty) {
      rows = rows
          .where((row) =>
              row.name.toLowerCase().contains(query) ||
              row.vendorName.toLowerCase().contains(query))
          .toList();
    }
    rows = switch (filter) {
      _AvailabilityFilter.all => rows,
      _AvailabilityFilter.available => rows.where((row) => row.available).toList(),
      _AvailabilityFilter.unavailable => rows.where((row) => !row.available).toList(),
    };

    if (rows.isEmpty) {
      return EmptyState(message: l10n.noProductsFoundMessage);
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        return Card(
          child: ListTile(
            leading: ClipRRect(
              borderRadius: AppRadius.small,
              child: row.imageUrl == null
                  ? Container(
                      width: 48,
                      height: 48,
                      color: VendorPalette.surfaceElevated,
                      child: const Icon(Icons.fastfood_outlined, color: VendorPalette.textMuted),
                    )
                  : AppNetworkImage(
                      imageUrl: row.imageUrl!,
                      width: 48,
                      height: 48,
                      borderRadius: AppRadius.small,
                    ),
            ),
            title: Text(row.name),
            subtitle: Text('${row.vendorName} · ${currencyFormat.format(row.price)}'),
            trailing: _AvailabilityBadge(available: row.available),
          ),
        ).staggeredEntrance(index);
      },
    );
  }
}

class _AvailabilityBadge extends StatelessWidget {
  const _AvailabilityBadge({required this.available});

  final bool available;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return StatusBadge(
      label: available ? l10n.availableLabel : l10n.unavailableLabel,
      tone: available ? StatusTone.success : StatusTone.neutral,
    );
  }
}
