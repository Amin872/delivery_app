import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/address.dart';
import '../../../routing/page_transitions.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
import 'edit_address_screen.dart';

final addressesProvider =
    StreamProvider.autoDispose.family<List<SavedAddress>, String>((ref, customerId) {
  return ref.watch(firestoreServiceProvider).watchAddresses(customerId);
});

// Also watched by CartScreen to prefill the delivery-address field.
final defaultAddressProvider =
    StreamProvider.autoDispose.family<SavedAddress?, String>((ref, customerId) {
  return ref.watch(firestoreServiceProvider).watchDefaultAddress(customerId);
});

/// "عنوان التوصيل" — the customer's saved delivery addresses: add, edit,
/// delete, and pick a default (used automatically by CartScreen). Same
/// [VendorPalette] theme as the rest of the Account/Profile subtree.
class DeliveryAddressesScreen extends ConsumerWidget {
  const DeliveryAddressesScreen({required this.customerId, super.key});

  final String customerId;

  Future<void> _deleteAddress(BuildContext context, WidgetRef ref, SavedAddress address) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      title: l10n.deleteAddressTitle,
      message: l10n.deleteAddressConfirmMessage,
      isDestructive: true,
    );
    if (confirmed != true) return;
    await ref.read(firestoreServiceProvider).deleteAddress(customerId, address.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final addressesAsync = ref.watch(addressesProvider(customerId));
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.deliveryAddressLabel),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: l10n.addAddressButton,
              onPressed: () => Navigator.of(context)
                  .push(fadeSlideRoute(EditAddressScreen(customerId: customerId))),
            ),
          ],
        ),
        body: ResponsiveCenter(
          child: addressesAsync.animatedWhen(
            data: (addresses) {
              if (addresses.isEmpty) {
                return _EmptyState(customerId: customerId);
              }
              return ListView.builder(
                padding: const EdgeInsets.all(AppSpacing.lg),
                itemCount: addresses.length,
                itemBuilder: (context, index) {
                  final address = addresses[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.md),
                    child: _AddressCard(
                      customerId: customerId,
                      address: address,
                      onDelete: () => _deleteAddress(context, ref, address),
                    ),
                  ).staggeredEntrance(index);
                },
              );
            },
            loading: () => const ListSkeletonLoader(),
            error: (error, _) => Center(
              child: Text(
                localizedErrorMessage(context, error),
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_on_outlined, size: 56, color: VendorPalette.textMuted),
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.noAddressAddedMessage,
              style: const TextStyle(color: VendorPalette.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context)
                    .push(fadeSlideRoute(EditAddressScreen(customerId: customerId))),
                icon: const Icon(Icons.add),
                label: Text(l10n.addAddressButton),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends ConsumerWidget {
  const _AddressCard({required this.customerId, required this.address, required this.onDelete});

  final String customerId;
  final SavedAddress address;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(color: colorScheme.surfaceContainer, borderRadius: AppRadius.large),
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: () => Navigator.of(context)
            .push(fadeSlideRoute(EditAddressScreen(customerId: customerId, address: address))),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.location_on_outlined, size: 18, color: colorScheme.primary),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      address.label.isEmpty ? l10n.deliveryAddressLabel : address.label,
                      style: textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (address.isDefault)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        borderRadius: AppRadius.pill,
                      ),
                      child: Text(
                        l10n.defaultAddressLabel,
                        style: textTheme.labelSmall
                            ?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w700),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                address.addressText,
                style: textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (address.coordinates == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(Icons.location_off_outlined, size: 14, color: colorScheme.error),
                      const SizedBox(width: 4),
                      Text(
                        l10n.noLocationSetMessage,
                        style: textTheme.labelSmall?.copyWith(color: colorScheme.error),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Flexible (not a bare TextButton) so this can shrink and
                  // ellipsize on narrow screens instead of overflowing the
                  // Row — this button's own width was previously
                  // unconstrained, which is what caused the debug-mode
                  // yellow/black RenderFlex overflow stripe on narrow
                  // viewports.
                  if (!address.isDefault)
                    Flexible(
                      child: TextButton(
                        onPressed: () => ref
                            .read(firestoreServiceProvider)
                            .setDefaultAddress(customerId, address.id),
                        child: Text(
                          l10n.setAsDefaultButton,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  IconButton(
                    icon: Icon(Icons.delete_outline, color: colorScheme.error),
                    tooltip: l10n.deleteTooltip,
                    onPressed: onDelete,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
