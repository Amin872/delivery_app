import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/format/display_formatters.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/providers/preferences_provider.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/image_picker_avatar.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/approval_status.dart';
import '../../../models/city.dart';
import '../../../models/coordinates.dart';
import '../../../models/order.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import '../../customer/screens/location_picker_screen.dart'
    show LocationPickerScreen, LocationPickResult;
import '../widgets/vendor_order_actions.dart' show isActiveVendorOrder;
import '../widgets/vendor_order_card.dart';
import 'menu_management_screen.dart' show MenuManagementScreen, storageServiceProvider;
import 'vendor_order_detail_screen.dart';
import 'vendor_stats_screen.dart';

final vendorOrdersProvider =
    StreamProvider.autoDispose.family<List<DeliveryOrder>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorOrders(vendorId);
});

final vendorSelfProvider = StreamProvider.autoDispose.family<Vendor, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendor(vendorId);
});

class VendorDashboardScreen extends ConsumerStatefulWidget {
  const VendorDashboardScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  ConsumerState<VendorDashboardScreen> createState() => _VendorDashboardScreenState();
}

class _VendorDashboardScreenState extends ConsumerState<VendorDashboardScreen> {
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

  // A failed write shows a localized snackbar; the switch keeps following
  // the vendor stream, so it snaps back to the stored value on its own.
  Future<void> _setOpen(bool value) async {
    HapticFeedback.selectionClick();
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await ref.read(firestoreServiceProvider).setVendorOpen(widget.vendorId, value);
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
      );
    }
  }

  void _onMoreAction(_VendorMoreAction action, Vendor? vendor) {
    switch (action) {
      case _VendorMoreAction.storeDetails:
        if (vendor != null) _openStoreDetailsForm(vendor);
      case _VendorMoreAction.storefrontPhoto:
        _changeStorefrontImage();
      case _VendorMoreAction.stats:
        Navigator.of(context).push(fadeSlideRoute(VendorStatsScreen(vendorId: widget.vendorId)));
      case _VendorMoreAction.language:
        ref.read(localeProvider.notifier).toggle();
      case _VendorMoreAction.signOut:
        ref.read(authServiceProvider).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vendorId = widget.vendorId;
    final vendorSelfAsync = ref.watch(vendorSelfProvider(vendorId));
    final vendorSelf = vendorSelfAsync.valueOrNull;
    final l10n = AppLocalizations.of(context)!;

    // Approval gate (UX only — security is already enforced by
    // firestore.rules, which stops self-approval, and by createOrder, which
    // rejects unapproved vendors). A pending vendor keeps the store-setup
    // actions (open switch, photos, details, menu) so their store is ready
    // the moment an admin approves it, but sees no orders or stats. A
    // rejected vendor gets no operational actions at all. Language and
    // sign-out stay available in every state.
    final approval = vendorSelf?.approvalStatus;
    final isApproved = approval == ApprovalStatus.approved;
    final canSetUpStore = vendorSelf != null && approval != ApprovalStatus.rejected;
    final title = switch (approval) {
      ApprovalStatus.approved => l10n.incomingOrdersTitle,
      ApprovalStatus.pending => l10n.vendorStoreSetupTitle,
      ApprovalStatus.rejected || null => l10n.vendorStoreTitle,
    };

    // Only the two everyday controls stay on the bar (store open/closed
    // and the menu); everything else lives in the "more" menu, so the bar
    // fits a 320px phone at any text scale.
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (canSetUpStore)
            Tooltip(
              message: l10n.vendorOpenTooltip,
              child: Switch(
                key: const ValueKey('vendor_open_switch'),
                value: vendorSelf.isOpen,
                onChanged: _setOpen,
              ),
            ),
          if (canSetUpStore)
            IconButton(
              icon: const Icon(Icons.restaurant_menu),
              tooltip: l10n.menuManagementTitle,
              onPressed: () => Navigator.of(context)
                  .push(fadeSlideRoute(MenuManagementScreen(vendorId: vendorId))),
            ),
          PopupMenuButton<_VendorMoreAction>(
            key: const ValueKey('vendor_more_menu'),
            tooltip: l10n.vendorMoreActionsTooltip,
            onSelected: (action) => _onMoreAction(action, vendorSelf),
            itemBuilder: (context) => [
              if (canSetUpStore) ...[
                _moreItem(_VendorMoreAction.storeDetails, Icons.storefront_outlined,
                    l10n.editStoreDetailsTooltip),
                _moreItem(_VendorMoreAction.storefrontPhoto, Icons.photo_camera_outlined,
                    l10n.changeStorefrontPhotoTooltip,
                    enabled: !_uploadingStorefrontImage),
              ],
              if (isApproved)
                _moreItem(_VendorMoreAction.stats, Icons.bar_chart, l10n.vendorStatsTitle),
              if (canSetUpStore || isApproved) const PopupMenuDivider(),
              _moreItem(_VendorMoreAction.language, Icons.translate, l10n.languageToggleTooltip),
              _moreItem(_VendorMoreAction.signOut, Icons.logout, l10n.signOutTooltip),
            ],
          ),
        ],
        // The storefront photo uploads in the background once picked.
        bottom: _uploadingStorefrontImage
            ? const PreferredSize(
                preferredSize: Size.fromHeight(AppSpacing.xs),
                child: LinearProgressIndicator(minHeight: AppSpacing.xs),
              )
            : null,
      ),
      body: ResponsiveCenter(
        child: vendorSelfAsync.animatedWhen(
          data: (vendor) => vendor.approvalStatus == ApprovalStatus.approved
              ? _VendorOrderList(vendorId: vendorId)
              : _ApprovalStatusView(status: vendor.approvalStatus),
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => ErrorState(error: error),
        ),
      ),
    );
  }
}

enum _VendorMoreAction { storeDetails, storefrontPhoto, stats, language, signOut }

PopupMenuItem<_VendorMoreAction> _moreItem(
  _VendorMoreAction action,
  IconData icon,
  String label, {
  bool enabled = true,
}) {
  return PopupMenuItem(
    value: action,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: AppSizes.iconLarge),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label)),
      ],
    ),
  );
}

/// The live orders list, shown only to an approved vendor: an
/// Active/Completed filter over the one [vendorOrdersProvider] stream
/// (client-side, no second query), then one [VendorOrderCard] per order,
/// each opening [VendorOrderDetailScreen].
class _VendorOrderList extends ConsumerStatefulWidget {
  const _VendorOrderList({required this.vendorId});

  final String vendorId;

  @override
  ConsumerState<_VendorOrderList> createState() => _VendorOrderListState();
}

class _VendorOrderListState extends ConsumerState<_VendorOrderList> {
  bool _showActive = true;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final countFormat = ref.watch(countFormatProvider);
    return ref.watch(vendorOrdersProvider(widget.vendorId)).animatedWhen(
          data: (orders) {
            if (orders.isEmpty) {
              return EmptyState(icon: Icons.receipt_long_outlined, message: l10n.noOrdersMessage);
            }
            final active = orders.where((o) => isActiveVendorOrder(o.status)).toList();
            final completed = orders.where((o) => !isActiveVendorOrder(o.status)).toList();
            final shown = _showActive ? active : completed;

            Widget filter(bool isActive, String label, int count) => ChoiceChip(
                  key: ValueKey(isActive ? 'vendor_filter_active' : 'vendor_filter_completed'),
                  label: Text('$label (${countFormat.format(count)})'),
                  selected: _showActive == isActive,
                  onSelected: (_) => setState(() => _showActive = isActive),
                );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                      AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.xs),
                  child: Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      filter(true, l10n.vendorOrdersActiveFilter, active.length),
                      filter(false, l10n.vendorOrdersCompletedFilter, completed.length),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? EmptyState(
                          icon: Icons.receipt_long_outlined,
                          message: _showActive
                              ? l10n.vendorNoActiveOrdersMessage
                              : l10n.vendorNoCompletedOrdersMessage,
                        )
                      : ListView.builder(
                          key: ValueKey('vendor_orders_${_showActive ? 'active' : 'completed'}'),
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          itemCount: shown.length,
                          itemBuilder: (context, index) {
                            final order = shown[index];
                            return VendorOrderCard(
                              key: ValueKey('vendor_order_${order.id}'),
                              order: order,
                              onTap: () => Navigator.of(context).push(fadeSlideRoute(
                                  VendorOrderDetailScreen(vendorId: widget.vendorId, orderId: order.id))),
                            ).staggeredEntrance(index);
                          },
                        ),
                ),
              ],
            );
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => ErrorState(error: error),
        );
  }
}

/// Shown instead of the orders list while the vendor isn't approved: the
/// shared [EmptyState] with the approval badge underneath.
class _ApprovalStatusView extends StatelessWidget {
  const _ApprovalStatusView({required this.status});

  final ApprovalStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRejected = status == ApprovalStatus.rejected;

    return EmptyState(
      key: ValueKey('vendor_approval_${status.name}'),
      icon: isRejected ? Icons.block_outlined : Icons.hourglass_top_outlined,
      title: isRejected ? l10n.vendorRejectedTitle : l10n.vendorPendingApprovalTitle,
      message: isRejected ? l10n.vendorRejectedMessage : l10n.vendorPendingApprovalMessage,
      action: ApprovalStatusBadge(status: status),
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
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _pickupAddressController;
  // Only ever set from LocationPickerScreen's result (or the saved vendor
  // doc) — never typed in by hand.
  Coordinates? _pickupCoordinates;
  // Mirrors the uploaded logo for this sheet's preview only; the vendor
  // stream stays the source of truth everywhere else.
  String? _logoUrl;
  File? _pendingLogo;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final vendor = widget.vendor;
    _nameController = TextEditingController(text: vendor.name);
    _descriptionController = TextEditingController(text: vendor.description);
    _pickupAddressController = TextEditingController(text: vendor.pickupAddress ?? '');
    _pickupCoordinates = (vendor.pickupLatitude != null && vendor.pickupLongitude != null)
        ? Coordinates(latitude: vendor.pickupLatitude!, longitude: vendor.pickupLongitude!)
        : null;
    _logoUrl = vendor.logoUrl;
    _category = widget.vendor.category;
    _city = widget.vendor.city;
    _feeController =
        TextEditingController(text: formatAmountForInput(widget.vendor.deliveryFee));
    _etaMinController = TextEditingController(text: widget.vendor.etaMinMinutes?.toString() ?? '');
    _etaMaxController = TextEditingController(text: widget.vendor.etaMaxMinutes?.toString() ?? '');
    _minOrderController =
        TextEditingController(text: formatAmountForInput(widget.vendor.minimumOrderAmount));
    _openTime = _hhmmToTimeOfDay(widget.vendor.openTime);
    _closeTime = _hhmmToTimeOfDay(widget.vendor.closeTime);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _pickupAddressController.dispose();
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

  // Reuses the customer address flow's map picker as-is: the pin comes
  // from the picker, and its reverse-geocoded text only pre-fills the
  // pickup address when the vendor hasn't typed one — they can always edit
  // it before saving.
  Future<void> _pickPickupLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      fadeSlideRoute(LocationPickerScreen(initialCoordinates: _pickupCoordinates)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _pickupCoordinates = result.coordinates;
      final suggested = result.geocodeResult?.formattedAddress;
      if (_pickupAddressController.text.trim().isEmpty && suggested != null) {
        _pickupAddressController.text = suggested;
      }
    });
  }

  // Uploads immediately on pick, like the dashboard's storefront photo —
  // to vendorImages/{vendorId}/logo.jpg, separate from storefront.jpg.
  Future<void> _uploadLogo(File file) async {
    setState(() => _pendingLogo = file);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final url = await ref
          .read(storageServiceProvider)
          .uploadVendorImage(widget.vendor.id, file, 'logo.jpg');
      await ref.read(firestoreServiceProvider).updateVendorLogo(widget.vendor.id, url);
      if (mounted) setState(() => _logoUrl = url);
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.logoUpdatedMessage));
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _pendingLogo = null);
    }
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
            name: _nameController.text,
            description: _descriptionController.text,
            updatePickupLocation: true,
            pickupAddress: _pickupAddressController.text,
            pickupLatitude: _pickupCoordinates?.latitude,
            pickupLongitude: _pickupCoordinates?.longitude,
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
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final pickup = _pickupCoordinates;
    // The sheet now holds more than fits a phone screen — scroll it.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.editStoreDetailsTitle, style: textTheme.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                Tooltip(
                  message: l10n.uploadLogoButton,
                  child: ImagePickerAvatar(
                    key: const ValueKey('vendor_logo_picker'),
                    radius: 32,
                    networkUrl: _logoUrl,
                    localFile: _pendingLogo,
                    // Ignore a second pick while one upload is in flight.
                    onPicked: _pendingLogo == null ? _uploadLogo : (_) {},
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.storeLogoTitle, style: textTheme.titleSmall),
                      Text(
                        l10n.storeLogoHint,
                        style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (_pendingLogo != null) buttonSpinner(colorScheme.primary, size: 16),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const ValueKey('store_name_field'),
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.storeNameFieldLabel),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l10n.storeNameRequiredError : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('store_description_field'),
              controller: _descriptionController,
              decoration: InputDecoration(labelText: l10n.storeDescriptionFieldLabel),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: AppSpacing.md),
            // isExpanded: a long category/city name ellipsizes inside the
            // field instead of overflowing it on narrow phones.
            DropdownButtonFormField<VendorCategory>(
              initialValue: _category,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.categoryFieldLabel),
              items: [
                for (final category in VendorCategory.values)
                  DropdownMenuItem(
                    value: category,
                    child: Text(vendorCategoryLabel(context, category), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                    child: Text(cityLabel(context, cityId, liveCities), maxLines: 1, overflow: TextOverflow.ellipsis),
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
                const SizedBox(width: AppSpacing.md),
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
            const SizedBox(height: AppSpacing.xl),
            Text(l10n.pickupLocationTitle, style: textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              pickup == null
                  ? l10n.pickupLocationNotSetMessage
                  : l10n.pickupPinSetLabel(formatCoordinates(pickup.latitude, pickup.longitude)),
              style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              key: const ValueKey('pickup_location_button'),
              onPressed: _pickPickupLocation,
              icon: const Icon(Icons.location_on_outlined),
              label: Text(pickup == null ? l10n.setPickupLocationButton : l10n.changePickupLocationButton),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('pickup_address_field'),
              controller: _pickupAddressController,
              decoration: InputDecoration(labelText: l10n.pickupAddressFieldLabel),
              minLines: 1,
              maxLines: 2,
              // Same rule the service enforces (validatePickupLocation): a
              // map pin needs readable address text for drivers.
              validator: (value) => validatePickupLocation(
                        address: value,
                        latitude: pickup?.latitude,
                        longitude: pickup?.longitude,
                      ) ==
                      PickupLocationError.addressRequired
                  ? l10n.pickupAddressRequiredError
                  : null,
            ),
            const SizedBox(height: AppSpacing.lg),
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
    if (parsed == null || parsed <= 0) return l10n.invalidEtaError;
    final min = int.tryParse(_etaMinController.text.trim());
    final max = int.tryParse(_etaMaxController.text.trim());
    if (min != null && max != null && min > max) return l10n.invalidEtaError;
    return null;
  }
}
