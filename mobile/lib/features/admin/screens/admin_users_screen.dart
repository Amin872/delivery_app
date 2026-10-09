import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/display_formatters.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/paging/paged_list_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_paged_list.dart';
import '../widgets/admin_scaffold.dart';

/// Read-only user directory — real `users/{uid}` data (id, email,
/// displayName, role, phoneNumber), 25 per page with "Load more". The
/// search runs on the server: a display-name prefix, or an email prefix
/// when the text contains `@` (see FirestoreService.fetchUsersPage). No
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

  late final PagedListController<AppUser> _users = PagedListController(
    idOf: (user) => user.id,
    fetchPage: (cursor) => ref.read(firestoreServiceProvider).fetchUsersPage(search: _query, after: cursor),
  );

  @override
  void initState() {
    super.initState();
    _users.refresh();
  }

  @override
  void dispose() {
    _users.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    if (query == _query) return;
    setState(() => _query = query);
    _users.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AdminScaffold(
      title: l10n.adminNavUsers,
      selected: AdminDestination.users,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminSearchField(
            hintText: l10n.searchUsersHint,
            helperText: l10n.searchStartsWithHelper,
            onChanged: _setQuery,
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: AdminPagedList<AppUser>(
              controller: _users,
              emptyMessage: l10n.noUsersFoundMessage,
              itemBuilder: (context, user, index) => Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: VendorPalette.surfaceElevated,
                    child: Text(
                      user.displayName.isNotEmpty ? user.displayName[0].toUpperCase() : '?',
                      style: const TextStyle(color: VendorPalette.textPrimary),
                    ),
                  ),
                  title: Text(user.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                  // Email and phone on their own lines: both are long LTR
                  // runs, and the phone is bidi-isolated so its "+" stays
                  // put inside Arabic text.
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis),
                      if (user.phoneNumber?.trim().isNotEmpty ?? false) Text(formatPhone(user.phoneNumber!)),
                    ],
                  ),
                  trailing: _RoleBadge(role: user.role),
                ),
              ).staggeredEntrance(index),
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
  Widget build(BuildContext context) => StatusBadge(label: userRoleLabel(context, role), tone: StatusTone.primary);
}
