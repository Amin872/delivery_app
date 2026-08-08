import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import 'admin_orders_screen.dart';

final pendingVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchPendingVendors();
});

class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(pendingVendorsProvider);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.vendorApprovalsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt_long),
            tooltip: l10n.adminOrdersTitle,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
            ),
          ),
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: vendorsAsync.when(
        data: (vendors) {
          if (vendors.isEmpty) {
            return Center(child: Text(l10n.noVendorsAwaitingApprovalMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: vendors.length,
            itemBuilder: (context, index) {
              final vendor = vendors[index];
              return Card(
                child: ListTile(
                  title: Text(vendor.name),
                  subtitle: Text(vendor.description.isEmpty
                      ? l10n.noDescriptionPlaceholder
                      : vendor.description),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle_outline),
                        tooltip: l10n.approveTooltip,
                        onPressed: () => ref
                            .read(firestoreServiceProvider)
                            .setVendorApprovalStatus(
                              vendor.id,
                              VendorApprovalStatus.approved,
                            ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: l10n.rejectTooltip,
                        onPressed: () => ref
                            .read(firestoreServiceProvider)
                            .setVendorApprovalStatus(
                              vendor.id,
                              VendorApprovalStatus.rejected,
                            ),
                      ),
                    ],
                  ),
                ),
              ).staggeredEntrance(index);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}
