import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/location/location_matcher.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/address.dart';
import '../../../models/coordinates.dart';
import '../../../models/neighborhood.dart';
import '../../../routing/page_transitions.dart';
import 'customer_home_screen.dart'
    show allCitiesProvider, allGovernoratesProvider, allNeighborhoodsProvider, firestoreServiceProvider;
import 'location_picker_screen.dart';

/// Finds the item in [items] whose [idOf] equals [id], or null if [id] is
/// null or nothing matches — avoids pulling in `package:collection` just
/// for `firstOrNull` over what's already a short, small-list lookup here.
T? _findById<T>(List<T> items, String? id, String Function(T) idOf) {
  if (id == null) return null;
  for (final item in items) {
    if (idOf(item) == id) return item;
  }
  return null;
}

/// Add or edit a single [SavedAddress] — Phase 4's map-first flow: a
/// [SavedAddress] always starts from a map pin (current location / manual
/// pick / search, via [LocationPickerScreen]) rather than free text alone.
/// The [addressText] field below remains a free-form description (per this
/// app's Syria-first addressing model — no street/building/apartment/
/// postal-code fields) but is now a supplement to the pin, not a
/// replacement for it — see models/address.dart's own doc comment on why
/// [SavedAddress.latitude]/[longitude] are the primary source of truth.
/// [address] null means "add new".
class EditAddressScreen extends ConsumerStatefulWidget {
  const EditAddressScreen({required this.customerId, this.address, super.key});

  final String customerId;
  final SavedAddress? address;

  @override
  ConsumerState<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends ConsumerState<EditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _labelController = TextEditingController(text: widget.address?.label ?? '');
  late final _addressController = TextEditingController(text: widget.address?.addressText ?? '');
  late final _instructionsController =
      TextEditingController(text: widget.address?.deliveryInstructions ?? '');
  late final _driverNoteController = TextEditingController(text: widget.address?.driverNote ?? '');
  late final _phoneController = TextEditingController(text: widget.address?.phone ?? '');
  late bool _isDefault = widget.address?.isDefault ?? false;
  bool _isSubmitting = false;
  String? _errorMessage;

  Coordinates? _coordinates;
  String? _governorateId;
  String? _cityId;
  String? _neighborhoodId;

  @override
  void initState() {
    super.initState();
    final existing = widget.address;
    _coordinates = existing?.coordinates;
    _governorateId = existing?.governorateId;
    _cityId = existing?.cityId;
    _neighborhoodId = existing?.neighborhoodId;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    _instructionsController.dispose();
    _driverNoteController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context).push<LocationPickResult>(
      fadeSlideRoute(LocationPickerScreen(initialCoordinates: _coordinates)),
    );
    if (result == null || !mounted) return;

    setState(() => _coordinates = result.coordinates);

    // Best-effort auto-fill from the reverse-geocode result — reconciled
    // against our own Firestore location hierarchy via LocationMatcher,
    // never written as a raw external-provider string. Left silently
    // unresolved (null) on no/ambiguous match — see
    // LocationMatchResult/NeighborhoodLocationMatchResult's own docs and
    // Phase 4 requirement #8 (neighborhoodId is never required).
    final geocodeResult = result.geocodeResult;
    if (geocodeResult != null) {
      final governorates = ref.read(allGovernoratesProvider).valueOrNull ?? const [];
      final cities = ref.read(allCitiesProvider).valueOrNull ?? const [];
      // D.1 fix: only match against enabled neighbourhoods — a disabled
      // record (e.g. a special-area/industrial/camp entry an admin
      // deliberately hid from the picker) must never be silently assigned
      // via reverse-geocoding auto-match either.
      final neighborhoods =
          visibleNeighborhoods(ref.read(allNeighborhoodsProvider).valueOrNull ?? const []);
      final match = matchNeighborhoodLocation(
        geocodeResult: geocodeResult,
        governorates: governorates,
        cities: cities,
        neighborhoods: neighborhoods,
      );
      setState(() {
        _governorateId = match.governorate?.id;
        _cityId = match.city?.id;
        _neighborhoodId = match.neighborhood?.id;
      });
      if (_addressController.text.trim().isEmpty && geocodeResult.formattedAddress != null) {
        _addressController.text = geocodeResult.formattedAddress!;
      }
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final service = ref.read(firestoreServiceProvider);
      final existing = widget.address;
      final address = SavedAddress(
        id: existing?.id ?? '',
        userId: widget.customerId,
        label: _labelController.text.trim(),
        latitude: _coordinates?.latitude,
        longitude: _coordinates?.longitude,
        governorateId: _governorateId,
        cityId: _cityId,
        neighborhoodId: _neighborhoodId,
        addressText: _addressController.text.trim(),
        deliveryInstructions:
            _instructionsController.text.trim().isEmpty ? null : _instructionsController.text.trim(),
        driverNote: _driverNoteController.text.trim().isEmpty ? null : _driverNoteController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        isDefault: existing?.isDefault ?? _isDefault,
      );
      if (existing == null) {
        await service.addAddress(widget.customerId, address);
      } else {
        await service.updateAddress(widget.customerId, address);
        if (_isDefault && !existing.isDefault) {
          await service.setDefaultAddress(widget.customerId, existing.id);
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final isEditing = widget.address != null;
    final cities = ref.watch(allCitiesProvider).valueOrNull ?? const [];
    final neighborhoods = ref.watch(allNeighborhoodsProvider).valueOrNull ?? const [];
    final governorates = ref.watch(allGovernoratesProvider).valueOrNull ?? const [];

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(isEditing ? l10n.editAddressTitle : l10n.addAddressButton),
        ),
        body: ResponsiveCenter(
          child: CenteredScrollBody(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _LocationSummaryCard(
                    coordinates: _coordinates,
                    governorateName: governorateLabel(
                      context,
                      _findById(governorates, _governorateId, (g) => g.id),
                    ),
                    cityName: _cityId == null ? null : cityLabel(context, _cityId!, cities),
                    neighborhoodName: neighborhoodLabel(
                      context,
                      _findById(neighborhoods, _neighborhoodId, (n) => n.id),
                    ),
                    onTap: _pickLocation,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_label_field'),
                    controller: _labelController,
                    decoration: InputDecoration(
                      labelText: l10n.addressLabelFieldLabel,
                      hintText: l10n.addressLabelHint,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_text_field'),
                    controller: _addressController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: l10n.deliveryAddressLabel,
                      hintText: l10n.addressFieldHint,
                      helperText: l10n.addressFieldHelperText,
                      helperMaxLines: 2,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_instructions_field'),
                    controller: _instructionsController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.deliveryInstructionsFieldLabel,
                      hintText: l10n.deliveryInstructionsHint,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_driver_note_field'),
                    controller: _driverNoteController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: l10n.driverNoteFieldLabel,
                      hintText: l10n.driverNoteHint,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_phone_field'),
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(labelText: l10n.addressPhoneFieldLabel),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    value: _isDefault,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l10n.setAsDefaultButton),
                    onChanged: (value) => setState(() => _isDefault = value ?? false),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: VendorPalette.textSecondary),
                      ),
                    ),
                  GradientButton(
                    key: const ValueKey('address_submit_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [VendorPalette.primaryCyan, VendorPalette.secondaryCyan],
                    ),
                    child: _isSubmitting
                        ? buttonSpinner(vendorTheme.colorScheme.onPrimary)
                        : Text(l10n.saveAddressButton),
                  ),
                ],
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
            ),
          ),
        ),
      ),
    );
  }
}

class _LocationSummaryCard extends StatelessWidget {
  const _LocationSummaryCard({
    required this.coordinates,
    required this.governorateName,
    required this.cityName,
    required this.neighborhoodName,
    required this.onTap,
  });

  final Coordinates? coordinates;
  final String? governorateName;
  final String? cityName;
  final String? neighborhoodName;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final hasPin = coordinates != null;
    final parts = [governorateName, cityName, neighborhoodName]
        .whereType<String>()
        .where((s) => s.isNotEmpty && s != l10n.governorateUnassignedLabel && s != l10n.neighborhoodUnassignedLabel)
        .toList();

    return Material(
      color: VendorPalette.surfaceContainer,
      borderRadius: AppRadius.large,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(
                hasPin ? Icons.location_on : Icons.add_location_alt_outlined,
                color: colorScheme.primary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasPin ? l10n.setLocationOnMapButton : l10n.noLocationSetMessage,
                      style: const TextStyle(
                          color: VendorPalette.textPrimary, fontWeight: FontWeight.w600),
                    ),
                    if (parts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          parts.join(' · '),
                          style: const TextStyle(color: VendorPalette.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: VendorPalette.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}
