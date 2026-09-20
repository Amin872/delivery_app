import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/order.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import 'menu_management_screen.dart' show MenuManagementScreen, storageServiceProvider;
import 'vendor_stats_screen.dart';

final vendorOrdersProvider =
    StreamProvider.autoDispose.family<List<DeliveryOrder>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorOrders(vendorId);
});

final vendorSelfProvider = StreamProvider.autoDispose.family<Vendor, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendor(vendorId);
});

// Beyond `readyForPickup`, only the `acceptDelivery` callable (driver side)
// advances an order further — see the architecture note in CLAUDE.md — so
// the vendor is offered no action past that point.
OrderStatus? _nextVendorStatus(OrderStatus current) {
  switch (current) {
    case OrderStatus.pending:
      return OrderStatus.accepted;
    case OrderStatus.accepted:
      return OrderStatus.preparing;
    case OrderStatus.preparing:
      return OrderStatus.readyForPickup;
    default:
      return null;
  }
}

// A vendor can only cancel while the order is still theirs to fulfill —
// once it's readyForPickup a driver may already be browsing it, and once
// picked up it's out of the vendor's hands entirely.
bool _vendorCanCancel(OrderStatus status) {
  return status == OrderStatus.pending ||
      status == OrderStatus.accepted ||
      status == OrderStatus.preparing;
}

class VendorDashboardScreen extends ConsumerStatefulWidget {
  const VendorDashboardScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  ConsumerState<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends ConsumerState<VendorDashboardScreen> {
  final _cancellingOrderIds = <String>{};
  bool _uploadingStorefrontImage = false;

  Future<void> _changeStorefrontImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null) return;
    if (!mounted) return;

    setState(() => _uploadingStorefrontImage = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final imageUrl = await ref
          .read(storageServiceProvider)
          .uploadVendorImage(widget.vendorId, File(picked.path), 'storefront.jpg');
      await ref.read(firestoreServiceProvider).updateVendorImage(widget.vendorId, imageUrl);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.storefrontImageUpdatedMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingStorefrontImage = false);
    }
  }

  Future<void> _openStoreDetailsForm(Vendor vendor) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _StoreDetailsForm(vendor: vendor),
      ),
    );
  }

  Future<void> _confirmCancel(DeliveryOrder order) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(context, message: l10n.cancelOrderConfirmMessage);
    if (confirmed != true) return;
    if (!mounted) return;

    HapticFeedback.lightImpact();
    setState(() => _cancellingOrderIds.add(order.id));
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(firestoreServiceProvider).cancelOrder(order.id);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.orderCancelledMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _cancellingOrderIds.remove(order.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorId = widget.vendorId;
    final ordersAsync = ref.watch(vendorOrdersProvider(vendorId));
    final vendorSelf = ref.watch(vendorSelfProvider(vendorId)).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.incomingOrdersTitle),
        actions: [
          if (vendorSelf != null)
            Tooltip(
              message: l10n.vendorOpenTooltip,
              child: Switch(
                key: const ValueKey('vendor_open_switch'),
                value: vendorSelf.isOpen,
                onChanged: (value) {
                  HapticFeedback.selectionClick();
                  ref.read(firestoreServiceProvider).setVendorOpen(vendorId, value);
                },
              ),
            ),
          IconButton(
            icon: _uploadingStorefrontImage
                ? buttonSpinner(Theme.of(context).colorScheme.onSurface, size: 16)
                : const Icon(Icons.photo_camera_outlined),
            tooltip: l10n.changeStorefrontPhotoTooltip,
            onPressed: _uploadingStorefrontImage ? null : _changeStorefrontImage,
          ),
          if (vendorSelf != null)
            IconButton(
              icon: const Icon(Icons.storefront_outlined),
              tooltip: l10n.editStoreDetailsTooltip,
              onPressed: () => _openStoreDetailsForm(vendorSelf),
            ),
          IconButton(
            icon: const Icon(Icons.bar_chart),
            tooltip: l10n.vendorStatsTitle,
            onPressed: () =>
                Navigator.of(context).push(fadeSlideRoute(VendorStatsScreen(vendorId: vendorId))),
          ),
          IconButton(
            icon: const Icon(Icons.restaurant_menu),
            tooltip: l10n.menuManagementTitle,
            onPressed: () => Navigator.of(context)
                .push(fadeSlideRoute(MenuManagementScreen(vendorId: vendorId))),
          ),
          const LanguageToggleButton(),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: l10n.signOutTooltip,
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ResponsiveCenter(
        child: ordersAsync.animatedWhen(
          data: (orders) {
          if (orders.isEmpty) {
            return Center(child: Text(l10n.noOrdersMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              final next = _nextVendorStatus(order.status);
              final isCancelling = _cancellingOrderIds.contains(order.id);
              return Card(
                child: ListTile(
                  title: Text(l10n.orderLabel(order.id)),
                  subtitle: Text(orderStatusLabel(context, order.status)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(currencyFormat.format(order.total)),
                      if (_vendorCanCancel(order.status))
                        IconButton(
                          icon: const Icon(Icons.cancel_outlined),
                          tooltip: l10n.cancelOrderButton,
                          color: Theme.of(context).colorScheme.error,
                          onPressed: isCancelling ? null : () => _confirmCancel(order),
                        ),
                      if (next != null) ...[
                        const SizedBox(width: 8),
                        // ListTile computes trailing's preferred width by
                        // asking it to lay out with unbounded constraints;
                        // TextButton's internal InputPadding does a real
                        // (non-dry) child layout() call during that probe,
                        // which throws on the resulting infinite width. A
                        // bounded ConstrainedBox absorbs the unbounded probe
                        // before it ever reaches TextButton.
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 140),
                          child: TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              ref
                                  .read(firestoreServiceProvider)
                                  .updateOrderStatus(order.id, next);
                            },
                            child: Text(
                              l10n.advanceStatusButtonLabel(orderStatusLabel(context, next)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
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
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
        ),
      ),
    );
  }
}

class _StoreDetailsForm extends ConsumerStatefulWidget {
  const _StoreDetailsForm({required this.vendor});

  final Vendor vendor;

  @override
  ConsumerState<_StoreDetailsForm> createState() => _StoreDetailsFormState();
}

class _StoreDetailsFormState extends ConsumerState<_StoreDetailsForm> {
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
    final liveCities = ref.watch(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final enabledCities = visibleCities(liveCities);
    // Selectable ids for a *new* choice are enabled-only (falling back to
    // the five legacy ids if the live list is empty) — but the vendor's
    // current city is always included even if it's disabled or has since
    // been removed from the live list, so opening this form never
    // silently reassigns an existing vendor away from their real city
    // (DropdownButtonFormField also requires `initialValue` to be among
    // `items`, so this is a correctness requirement, not just a nicety).
    final selectableCityIds = enabledCities.isNotEmpty
        ? enabledCities.map((c) => c.id).toList()
        : List<String>.from(legacyCityIds);
    if (!selectableCityIds.contains(_city)) {
      selectableCityIds.add(_city);
    }
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
            DropdownButtonFormField<String>(
              initialValue: _city,
              decoration: InputDecoration(labelText: l10n.cityFieldLabel),
              items: [
                for (final cityId in selectableCityIds)
                  DropdownMenuItem(value: cityId, child: Text(cityLabel(context, cityId, liveCities))),
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
