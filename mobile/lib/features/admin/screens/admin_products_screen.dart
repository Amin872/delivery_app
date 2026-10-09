import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/paging/paged_list_controller.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_paged_list.dart';
import '../widgets/admin_scaffold.dart';

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

/// Joins products (one admin page of them) with their vendors' names.
/// Pure/Firebase-free so the join is unit-testable independent of the
/// queries — same reasoning as Drivers' `buildDriverRows`. A product whose vendor doc is missing is still shown
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

bool? _availabilityValue(_AvailabilityFilter filter) => switch (filter) {
      _AvailabilityFilter.all => null,
      _AvailabilityFilter.available => true,
      _AvailabilityFilter.unavailable => false,
    };

/// Read-only admin product browser across every vendor — no edit/delete/
/// delist here (Phase 4 Products is read-only; `menuItems` write rules are
/// unchanged), just visibility the admin panel didn't have before. 25 per
/// page with "Load more" (FirestoreService.fetchMenuItemsPage, an admin
/// query separate from the customer feed's); the availability chips and
/// the product-name prefix search run on the server, and each page's
/// vendor names come from one batch read of just those vendors.
class AdminProductsScreen extends ConsumerStatefulWidget {
  const AdminProductsScreen({super.key});

  @override
  ConsumerState<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends ConsumerState<AdminProductsScreen> {
  String _query = '';
  _AvailabilityFilter _filter = _AvailabilityFilter.all;

  late final PagedListController<ProductRow> _products = PagedListController(
    // Item ids are only unique within their vendor's subcollection.
    idOf: (row) => '${row.vendorId}/${row.itemId}',
    fetchPage: (cursor) async {
      final service = ref.read(firestoreServiceProvider);
      final page = await service.fetchMenuItemsPage(
        available: _availabilityValue(_filter),
        namePrefix: _query,
        after: cursor,
      );
      final vendors = await service.fetchVendorsByIds(page.items.map((item) => item.vendorId));
      return page.withItems(buildProductRows(page.items, vendors.values.toList()));
    },
  );

  @override
  void initState() {
    super.initState();
    _products.refresh();
  }

  @override
  void dispose() {
    _products.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    if (query == _query) return;
    setState(() => _query = query);
    _products.refresh();
  }

  void _setFilter(_AvailabilityFilter filter) {
    if (filter == _filter) return;
    setState(() => _filter = filter);
    _products.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);

    return AdminScaffold(
      title: l10n.adminNavProducts,
      selected: AdminDestination.products,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSearchField(
            hintText: l10n.searchProductsHint,
            helperText: l10n.searchStartsWithHelper,
            onChanged: _setQuery,
          ),
          const SizedBox(height: AppSpacing.md),
          AdminFilterChipBar(
            chips: [
              _FilterChip(
                label: l10n.allStatusesLabel,
                selected: _filter == _AvailabilityFilter.all,
                onSelected: () => _setFilter(_AvailabilityFilter.all),
              ),
              _FilterChip(
                label: l10n.availableLabel,
                selected: _filter == _AvailabilityFilter.available,
                onSelected: () => _setFilter(_AvailabilityFilter.available),
              ),
              _FilterChip(
                label: l10n.unavailableLabel,
                selected: _filter == _AvailabilityFilter.unavailable,
                onSelected: () => _setFilter(_AvailabilityFilter.unavailable),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: AdminPagedList<ProductRow>(
              controller: _products,
              emptyMessage: l10n.noProductsFoundMessage,
              itemBuilder: (context, row, index) => Card(
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
                  title: Text(row.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${row.vendorName} · ${currencyFormat.format(row.price)}'),
                  trailing: _AvailabilityBadge(available: row.available),
                ),
              ).staggeredEntrance(index),
            ),
          ),
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
