import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../widgets/customer_order_tile.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final customerOrdersProvider =
    StreamProvider.autoDispose.family<List<DeliveryOrder>, String>((ref, customerId) {
  return ref.watch(firestoreServiceProvider).watchCustomerOrders(customerId);
});

/// Same [VendorPalette] theme as CustomerHomeScreen/AccountScreen — this
/// screen used to run on the separate ambient `AppTheme` (a different,
/// burgundy-seeded palette), which is the inconsistency this pass fixes.
///
/// The customer's orders split into Active (still moving) and Past
/// (delivered/cancelled), both from the one [customerOrdersProvider]
/// stream (newest first) — filtered client-side, no second query.
class MyOrdersScreen extends ConsumerWidget {
  const MyOrdersScreen({required this.customerId, super.key});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(customerOrdersProvider(customerId));
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.myOrdersTitle),
          actions: const [LanguageToggleButton()],
        ),
        body: ResponsiveCenter(
          child: ordersAsync.animatedWhen(
            data: (orders) {
              if (orders.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noOrdersMessage,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                );
              }
              final active = orders.where(isActiveCustomerOrder).toList();
              final past = orders.where((o) => !isActiveCustomerOrder(o)).toList();
              var index = 0;
              return ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _SectionHeader(key: const ValueKey('active_orders_header'), title: l10n.activeOrdersTitle),
                  if (active.isEmpty)
                    _SectionEmpty(message: l10n.noActiveOrdersMessage)
                  else
                    for (final order in active)
                      CustomerOrderTile(key: ValueKey('order_${order.id}'), order: order)
                          .staggeredEntrance(index++),
                  _SectionHeader(key: const ValueKey('past_orders_header'), title: l10n.pastOrdersTitle),
                  if (past.isEmpty)
                    _SectionEmpty(message: l10n.noPastOrdersMessage)
                  else
                    for (final order in past)
                      CustomerOrderTile(key: ValueKey('order_${order.id}'), order: order)
                          .staggeredEntrance(index++),
                ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(color: VendorPalette.textSecondary),
        ),
      ),
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  const _SectionEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      child: Text(message, style: const TextStyle(color: VendorPalette.textSecondary)),
    );
  }
}
