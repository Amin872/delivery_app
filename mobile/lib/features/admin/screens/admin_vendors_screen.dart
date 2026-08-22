import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';

/// Full restaurant directory (any approvalStatus/isOpen), unlike
/// [pendingVendorsProvider] (approval queue only, still used by
/// AdminDashboardScreen's count card).
final allVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllVendors();
});

/// Restaurant Management — every vendor regardless of approval/open state,
/// searchable and filterable, with approve/reject for pending vendors (the
/// original behavior, unchanged), an admin enable/disable toggle, and an
/// edit-details form reusing the same `updateVendorDetails` the vendor's own
/// dashboard uses (see `_StoreDetailsForm` in vendor_dashboard_screen.dart).
class AdminVendorsScreen extends ConsumerStatefulWidget {
  const AdminVendorsScreen({super.key});

  @override
  ConsumerState<AdminVendorsScreen> createState() => _AdminVendorsScreenState();
}

class _AdminVendorsScreenState extends ConsumerState<AdminVendorsScreen> {
  String _query = '';
  VendorApprovalStatus? _statusFilter;

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

  @override
  Widget build(BuildContext context) {
    final vendorsAsync = ref.watch(allVendorsProvider);
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
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(l10n.allStatusesLabel),
                    selected: _statusFilter == null,
                    onSelected: (_) => setState(() => _statusFilter = null),
                  ),
                ),
                for (final status in VendorApprovalStatus.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(vendorApprovalStatusLabel(context, status)),
                      selected: _statusFilter == status,
                      onSelected: (_) => setState(() => _statusFilter = status),
                    ),
                  ),
              ],
            ),
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
                  return Center(child: Text(l10n.noVendorsFoundMessage));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final vendor = filtered[index];
                    return Card(
                      child: ListTile(
                        isThreeLine: true,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(vendor.name, overflow: TextOverflow.ellipsis),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(status: vendor.approvalStatus),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${vendorCategoryLabel(context, vendor.category)} · ${cityLabel(context, vendor.city)}',
                            ),
                            Text(
                              vendor.description.isEmpty
                                  ? l10n.noDescriptionPlaceholder
                                  : vendor.description,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (vendor.approvalStatus == VendorApprovalStatus.approved)
                              Tooltip(
                                message: l10n.vendorOpenTooltip,
                                child: Switch(
                                  value: vendor.isOpen,
                                  onChanged: (value) {
                                    HapticFeedback.selectionClick();
                                    ref
                                        .read(firestoreServiceProvider)
                                        .setVendorOpen(vendor.id, value);
                                  },
                                ),
                              ),
                            IconButton(
                              icon: const Icon(Icons.storefront_outlined),
                              tooltip: l10n.editStoreDetailsTooltip,
                              onPressed: () => _openEditForm(vendor),
                            ),
                            if (vendor.approvalStatus == VendorApprovalStatus.pending) ...[
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
                          ],
                        ),
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

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final VendorApprovalStatus status;

  Color get _color => switch (status) {
        VendorApprovalStatus.pending => Colors.orange,
        VendorApprovalStatus.approved => Colors.green,
        VendorApprovalStatus.rejected => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: VendorPalette.surfaceElevated, borderRadius: AppRadius.pill),
      child: Text(
        vendorApprovalStatusLabel(context, status),
        style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 12),
      ),
    );
  }
}

/// Admin's edit-details form — same fields and same
/// `FirestoreService.updateVendorDetails` call as the vendor's own
/// `_StoreDetailsForm` (vendor_dashboard_screen.dart); kept as a separate
/// widget rather than shared/exported since the two live in different
/// features and nothing else needs to reuse it yet.
class _AdminVendorEditForm extends ConsumerStatefulWidget {
  const _AdminVendorEditForm({required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<_AdminVendorEditForm> createState() => _AdminVendorEditFormState();
}

class _AdminVendorEditFormState extends ConsumerState<_AdminVendorEditForm> {
  final _formKey = GlobalKey<FormState>();
  late VendorCategory _category;
  late City _city;
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
    _feeController =
        TextEditingController(text: widget.vendor.deliveryFee?.toStringAsFixed(2) ?? '');
    _etaMinController = TextEditingController(text: widget.vendor.etaMinMinutes?.toString() ?? '');
    _etaMaxController = TextEditingController(text: widget.vendor.etaMaxMinutes?.toString() ?? '');
    _minOrderController =
        TextEditingController(text: widget.vendor.minimumOrderAmount?.toStringAsFixed(2) ?? '');
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.editStoreDetailsTitle, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            DropdownButtonFormField<VendorCategory>(
              initialValue: _category,
              decoration: InputDecoration(labelText: l10n.categoryFieldLabel),
              items: [
                for (final category in VendorCategory.values)
                  DropdownMenuItem(value: category, child: Text(vendorCategoryLabel(context, category))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<City>(
              initialValue: _city,
              decoration: InputDecoration(labelText: l10n.cityFieldLabel),
              items: [
                for (final city in City.values)
                  DropdownMenuItem(value: city, child: Text(cityLabel(context, city))),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _city = value);
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _feeController,
              decoration: InputDecoration(labelText: l10n.deliveryFeeFieldLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                return double.tryParse(value.trim()) == null ? l10n.invalidPriceError : null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _etaMinController,
                    decoration: InputDecoration(labelText: l10n.etaMinFieldLabel),
                    keyboardType: TextInputType.number,
                    validator: (value) => _validateEta(value, l10n),
                  ),
                ),
                const SizedBox(width: 12),
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
            const SizedBox(height: 12),
            TextFormField(
              controller: _minOrderController,
              decoration: InputDecoration(labelText: l10n.minimumOrderFieldLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.trim().isEmpty) return null;
                return double.tryParse(value.trim()) == null ? l10n.invalidPriceError : null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isOpenTime: true),
                    child: Text(
                      _openTime == null
                          ? l10n.openTimeFieldLabel
                          : '${l10n.openTimeFieldLabel}: ${_openTime!.format(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _pickTime(isOpenTime: false),
                    child: Text(
                      _closeTime == null
                          ? l10n.closeTimeFieldLabel
                          : '${l10n.closeTimeFieldLabel}: ${_closeTime!.format(context)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_errorMessage != null)
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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

  String? _validateEta(String? value, AppLocalizations l10n) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed <= 0) return l10n.invalidPriceError;
    final min = int.tryParse(_etaMinController.text.trim());
    final max = int.tryParse(_etaMaxController.text.trim());
    if (min != null && max != null && min > max) return l10n.invalidPriceError;
    return null;
  }
}
