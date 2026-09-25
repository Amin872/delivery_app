import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';

final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllUsers();
});

/// Read-only user directory — real `users/{uid}` data (id, email,
/// displayName, role, phoneNumber), search-filtered client-side. No
/// enable/disable, delete, or role-change actions: [AppUser] has no
/// `disabled` field and role changes must not be a client-writable
/// operation (see ADMIN_AUDIT_REPORT.md §2/§15) — those need a schema and
/// rules decision this phase deliberately doesn't make.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final usersAsync = ref.watch(allUsersProvider);

    return AdminScaffold(
      title: l10n.adminNavUsers,
      selected: AdminDestination.users,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.searchUsersHint,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              filled: true,
              fillColor: VendorPalette.surfaceContainer,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: usersAsync.animatedWhen(
              data: (users) {
                final filtered = _query.isEmpty
                    ? users
                    : users
                        .where((user) =>
                            user.displayName.toLowerCase().contains(_query) ||
                            user.email.toLowerCase().contains(_query))
                        .toList();
                if (filtered.isEmpty) {
                  return Center(child: Text(l10n.noUsersFoundMessage));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final user = filtered[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: VendorPalette.surfaceElevated,
                          child: Text(
                            user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                            style: const TextStyle(color: VendorPalette.textPrimary),
                          ),
                        ),
                        title: Text(user.displayName),
                        subtitle: Text(
                          user.phoneNumber == null ? user.email : '${user.email} · ${user.phoneNumber}',
                        ),
                        trailing: _RoleBadge(role: user.role),
                      ),
                    ).staggeredEntrance(index);
                  },
                );
              },
              loading: () => const ListSkeletonLoader(),
              error: (error, _) => Center(child: Text(localizedErrorMessage(context, error))),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.role});

  final UserRole role;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: VendorPalette.surfaceElevated, borderRadius: AppRadius.pill),
      child: Text(
        userRoleLabel(context, role),
        style: const TextStyle(
          color: VendorPalette.primaryCyan,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }
}
