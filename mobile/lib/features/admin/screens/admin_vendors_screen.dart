import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/format/display_formatters.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_scaffold.dart';
import '../../../core/widgets/state_views.dart';

/// Full restaurant directory (any approvalStatus/isOpen), unlike
/// [pendingVendorsProvider] (approval queue only, still used by
/// AdminDashboardScreen's count card).
final allVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllVendors();
});

/// Restaurant Management — every vendor regardless of approval/open state,
/// searchable and filterable. A pending vendor shows Approve / Reject
/// buttons on its card; an already-decided vendor can be reversed (approve
/// a rejected one, reject an approved one) from the card's overflow menu,
/// which also holds the edit-details form (the same `updateVendorDetails`
/// the vendor's own dashboard uses). Every approval change and closing an
/// open restaurant asks for confirmation first; firestore.rules is still
/// what decides whether the write is allowed.
class AdminVendorsScreen extends ConsumerStatefulWidget {
  const AdminVendorsScreen({super.key});

  @override
  ConsumerState<AdminVendorsScreen> createState() => _AdminVendorsScreenState();
}

class _AdminVendorsScreenState extends ConsumerState<AdminVendorsScreen> {
  String _query = '';
  VendorApprovalStatus? _statusFilter;
  // Vendors with an approval write in flight — their actions are disabled
  // until it settles, so a double tap can't send twice.
  final Set<String> _approvalBusy = {};

  Future<void> _openEditForm(Vendor vendor) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _AdminVendorEditForm(vendor: vendor),
      ),
    );
  }

  Future<void> _setApproval(Vendor vendor, VendorApprovalStatus status) async {
    if (_approvalBusy.contains(vendor.id)) return;
    final l10n = AppLocalizations.of(context)!;
    final approve = status == VendorApprovalStatus.approved;
    final confirmed = await showConfirmDialog(
      context,
      title: approve ? l10n.vendorApproveConfirmTitle : l10n.vendorRejectConfirmTitle,
      message: approve ? l10n.vendorApproveConfirmMessage(vendor.name) : l10n.vendorRejectConfirmMessage(vendor.name),
      isDestructive: !approve,
    );
    if (confirmed != true || !mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _approvalBusy.add(vendor.id));
    await runAdminWrite(
      context,
      () => ref.read(firestoreServiceProvider).setVendorApprovalStatus(vendor.id, status),
      successMessage: approve ? l10n.vendorApprovedMessage : l10n.vendorRejectedByAdminMessage,
    );
    if (mounted) setState(() => _approvalBusy.remove(vendor.id));
  }

  /// Opening is immediate; closing a live restaurant stops its orders, so
  /// it's confirmed first. Resolves false when backed out or failed, so the
  /// switch rolls back.
  Future<bool> _setOpen(Vendor vendor, bool open) async {
    if (!open) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showConfirmDialog(context, message: l10n.vendorCloseConfirmMessage(vendor.name));
      if (confirmed != true || !mounted) return false;
    }
    HapticFeedback.selectionClick();
    return runAdminWrite(context, () => ref.read(firestoreServiceProvider).setVendorOpen(vendor.id, open));
  }

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(allVendorsProvider);
    final liveCities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final l10n = AppLocalizations.of(context)!;

    return AdminScaffold(
      title: l10n.restaurantManagementTitle,
      selected: AdminDestination.vendors,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.searchVendorsHint,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              filled: true,
              fillColor: VendorPalette.surfaceContainer,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
            onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          ),
          const SizedBox(height: AppSpacing.md),
          AdminFilterChipBar(
            chips: [
              ChoiceChip(
                label: Text(l10n.allStatusesLabel),
                selected: _statusFilter == null,
                onSelected: (_) => setState(() => _statusFilter = null),
              ),
              for (final status in VendorApprovalStatus.values)
                ChoiceChip(
                  label: Text(vendorApprovalStatusLabel(context, status)),
                  selected: _statusFilter == status,
                  onSelected: (_) => setState(() => _statusFilter = status),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Expanded(
            child: vendorsAsync.animatedWhen(
              data: (vendors) {
                final filtered = vendors.where((vendor) {
                  final matchesQuery =
                      _query.isEmpty || vendor.name.toLowerCase().contains(_query);
                  final matchesStatus =
                      _statusFilter == null || vendor.approvalStatus == _statusFilter;
                  return matchesQuery && matchesStatus;
                }).toList();
                if (filtered.isEmpty) {
                  return EmptyState(message: l10n.noVendorsFoundMessage);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final vendor = filtered[index];
                    return _VendorCard(
                      key: ValueKey('admin_vendor_${vendor.id}'),
                      vendor: vendor,
                      cities: liveCities,
                      busy: _approvalBusy.contains(vendor.id),
                      onEdit: () => _openEditForm(vendor),
                      onSetApproval: (status) => _setApproval(vendor, status),
                      onSetOpen: (open) => _setOpen(vendor, open),
                    ).staggeredEntrance(index);
                  },
                );
              },
              loading: () => const ListSkeletonLoader(),
              error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(allVendorsProvider)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _VendorAction { edit, approve, reject }

/// One restaurant: name and location with the full row width (the edit /
/// approval-reversal actions sit in a small overflow menu), then its
/// approval badge beside the open/closed switch (approved only), and — for
/// a pending vendor — full-width Approve / Reject buttons, so the decision
/// an admin is most often here to make is never hidden in a menu.
class _VendorCard extends StatelessWidget {
  const _VendorCard({
    required this.vendor,
    required this.cities,
    required this.busy,
    required this.onEdit,
    required this.onSetApproval,
    required this.onSetOpen,
    super.key,
  });

  final Vendor vendor;
  final List<CityOption> cities;
  final bool busy;
  final VoidCallback onEdit;
  final ValueChanged<VendorApprovalStatus> onSetApproval;
  final Future<bool> Function(bool open) onSetOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final status = vendor.approvalStatus;
    final isPending = status == VendorApprovalStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.md, AppSpacing.xs, AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        vendor.name,
                        style: textTheme.titleSmall,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${vendorCategoryLabel(context, vendor.category)} · ${cityLabel(context, vendor.city, cities)}',
                        style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                      ),
                      Text(
                        vendor.description.isEmpty ? l10n.noDescriptionPlaceholder : vendor.description,
                        style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (busy)
                  SizedBox.square(
                    key: ValueKey('admin_vendor_busy_${vendor.id}'),
                    dimension: AppSizes.minTapTarget,
                    child: Center(child: buttonSpinner(colorScheme.primary, size: AppSizes.iconMedium)),
                  )
                else
                  PopupMenuButton<_VendorAction>(
                    key: ValueKey('admin_vendor_actions_${vendor.id}'),
                    tooltip: l10n.vendorMoreActionsTooltip,
                    onSelected: (action) => switch (action) {
                      _VendorAction.edit => onEdit(),
                      _VendorAction.approve => onSetApproval(VendorApprovalStatus.approved),
                      _VendorAction.reject => onSetApproval(VendorApprovalStatus.rejected),
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _VendorAction.edit,
                        child: AdminMenuItemLabel(icon: Icons.storefront_outlined, label: l10n.editStoreDetailsTooltip),
                      ),
                      // Pending vendors get these as buttons below instead.
                      if (status == VendorApprovalStatus.rejected)
                        PopupMenuItem(
                          value: _VendorAction.approve,
                          child: AdminMenuItemLabel(icon: Icons.check_circle_outline, label: l10n.approveTooltip),
                        ),
                      if (status == VendorApprovalStatus.approved)
                        PopupMenuItem(
                          value: _VendorAction.reject,
                          child: AdminMenuItemLabel(
                            icon: Icons.cancel_outlined,
                            label: l10n.rejectTooltip,
                            color: colorScheme.error,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
              child: Row(
                children: [
                  Flexible(child: ApprovalStatusBadge(status: status)),
                  const Spacer(),
                  if (status == VendorApprovalStatus.approved)
                    AdminAsyncSwitch(
                      key: ValueKey('admin_vendor_open_${vendor.id}'),
                      value: vendor.isOpen,
                      tooltip: l10n.vendorOpenTooltip,
                      onChanged: onSetOpen,
                    ),
                ],
              ),
            ),
            if (isPending) ...[
              const SizedBox(height: AppSpacing.sm),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: AppSpacing.md),
                child: Row(
                  children: [
                    // Text-only (no icons): two half-width buttons on a
                    // 320px phone at 1.3× text have no room to spare.
                    Expanded(
                      child: FilledButton(
                        key: ValueKey('admin_vendor_approve_${vendor.id}'),
                        onPressed: busy ? null : () => onSetApproval(VendorApprovalStatus.approved),
                        child: Text(l10n.approveTooltip, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: OutlinedButton(
                        key: ValueKey('admin_vendor_reject_${vendor.id}'),
                        onPressed: busy ? null : () => onSetApproval(VendorApprovalStatus.rejected),
                        style: OutlinedButton.styleFrom(foregroundColor: colorScheme.error),
                        child: Text(l10n.rejectTooltip, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Admin's edit-details form — same fields and same
/// `FirestoreService.updateVendorDetails` call as the vendor's own
/// `_StoreDetailsForm` (vendor_dashboard_screen.dart); kept as a separate
/// widget rather than shared/exported since the two live in different
/// features and nothing else needs to reuse it yet. Scrolls, so it stays
/// usable on a short phone with the keyboard open or a large text scale.
class _AdminVendorEditForm extends ConsumerStatefulWidget {
  const _AdminVendorEditForm({required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<_AdminVendorEditForm> createState() => _AdminVendorEditFormState();
}

class _AdminVendorEditFormState extends ConsumerState<_AdminVendorEditForm> {
  final _formKey = GlobalKey<FormState>();
  late VendorCategory _category;
  late String _city;
  late final TextEditingController _feeController;
  late final TextEditingController _etaMinController;
  late final TextEditingController _etaMaxController;
  late final TextEditingController _minOrderController;
  TimeOfDay? _openTime;
  TimeOfDay? _closeTime;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _category = widget.vendor.category;
    _city = widget.vendor.city;
    _feeController = TextEditingController(text: formatAmountForInput(widget.vendor.deliveryFee));
    _etaMinController = TextEditingController(text: widget.vendor.etaMinMinutes?.toString() ?? '');
    _etaMaxController = TextEditingController(text: widget.vendor.etaMaxMinutes?.toString() ?? '');
    _minOrderController = TextEditingController(text: formatAmountForInput(widget.vendor.minimumOrderAmount));
    _openTime = _hhmmToTimeOfDay(widget.vendor.openTime);
    _closeTime = _hhmmToTimeOfDay(widget.vendor.closeTime);
  }

  @override
  void dispose() {
    _feeController.dispose();
    _etaMinController.dispose();
    _etaMaxController.dispose();
    _minOrderController.dispose();
    super.dispose();
  }

  static TimeOfDay? _hhmmToTimeOfDay(String? value) {
    if (value == null) return null;
    final parts = value.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  static String _timeOfDayToHHmm(TimeOfDay time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickTime({required bool isOpenTime}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (isOpenTime ? _openTime : _closeTime) ?? TimeOfDay.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isOpenTime) {
        _openTime = picked;
      } else {
        _closeTime = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(firestoreServiceProvider).updateVendorDetails(
            widget.vendor.id,
            category: _category,
            city: _city,
            deliveryFee: double.tryParse(_feeController.text.trim()),
            etaMinMinutes: int.tryParse(_etaMinController.text.trim()),
            etaMaxMinutes: int.tryParse(_etaMaxController.text.trim()),
            minimumOrderAmount: double.tryParse(_minOrderController.text.trim()),
            openTime: _openTime == null ? null : _timeOfDayToHHmm(_openTime!),
            closeTime: _closeTime == null ? null : _timeOfDayToHHmm(_closeTime!),
          );
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          buildAppSnackBar(Theme.of(context).colorScheme, l10n.storeDetailsUpdatedMessage),
        );
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = localizedErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final liveCities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final enabledCities = visibleCities(liveCities);
    // Same "preserve current, enabled-only for new" reasoning as
    // vendor_dashboard_screen.dart's _StoreDetailsForm — an admin editing a
    // vendor must never silently move it off a disabled/stale city either.
    final selectableCityIds = enabledCities.isNotEmpty
        ? enabledCities.map((c) => c.id).toList()
        : List<String>.from(legacyCityIds);
    if (!selectableCityIds.contains(_city)) {
      selectableCityIds.add(_city);
    }
    return SingleChildScrollView(
      key: const ValueKey('admin_vendor_edit_form'),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.editStoreDetailsTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            DropdownButtonFormField<VendorCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.categoryFieldLabel),
              items: [
                for (final category in VendorCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(vendorCategoryLabel(context, category), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String>(
              initialValue: _city,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.cityFieldLabel),
              items: [
                for (final cityId in selectableCityIds)
                  DropdownMenuItem(
                    value: cityId,
                    child: Text(cityLabel(context, cityId, liveCities), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _city = value);
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _feeController,
              decoration: InputDecoration(labelText: l10n.deliveryFeeFieldLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                return double.tryParse(value.trim()) == null ? l10n.invalidPriceError : null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _etaMinController,
                    decoration: InputDecoration(labelText: l10n.etaMinFieldLabel),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateEta(value, l10n),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _etaMaxController,
                    decoration: InputDecoration(labelText: l10n.etaMaxFieldLabel),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateEta(value, l10n),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _minOrderController,
              decoration: InputDecoration(labelText: l10n.minimumOrderFieldLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                return double.tryParse(value.trim()) == null ? l10n.invalidPriceError : null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            // Stacked rather than side by side: "Opening time: 10:00 AM"
            // doesn't fit half a 320px sheet in Arabic at a large text scale.
            OutlinedButton(
              onPressed: () => _pickTime(isOpenTime: true),
              child: Text(
                _openTime == null
                    ? l10n.openTimeFieldLabel
                    : '${l10n.openTimeFieldLabel}: ${_openTime!.format(context)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton(
              onPressed: () => _pickTime(isOpenTime: false),
              child: Text(
                _closeTime == null
                    ? l10n.closeTimeFieldLabel
                    : '${l10n.closeTimeFieldLabel}: ${_closeTime!.format(context)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            GradientButton(
              onPressed: _isSubmitting ? null : _save,
              child: _isSubmitting
                  ? buttonSpinner(Theme.of(context).colorScheme.onPrimary)
                  : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }

  /// Same rule and message as the vendor's own store-details form: whole
  /// positive minutes, and the minimum never above the maximum.
  String? _validateEta(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return l10n.invalidEtaError;
    final min = int.tryParse(_etaMinController.text.trim());
    final max = int.tryParse(_etaMaxController.text.trim());
    if (min != null && max != null && min > max) return l10n.invalidEtaError;
    return null;
  }
}
