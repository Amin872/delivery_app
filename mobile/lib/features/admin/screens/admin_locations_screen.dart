import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/city.dart';
import '../../../models/governorate.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import '../widgets/admin_scaffold.dart';
import 'admin_vendors_screen.dart' show allVendorsProvider;

final allGovernoratesProvider = StreamProvider<List<GovernorateOption>>((ref) {
  return ref.watch(firestoreServiceProvider).watchGovernorates();
});

/// One city joined with its resolved governorate (or null — "unassigned",
/// covering both a genuinely-null `governorateId` and a `governorateId`
/// that doesn't match any currently-loaded governorate, e.g. a stale/
/// removed reference). Deliberately carries the full [GovernorateOption]
/// (not a pre-resolved name string) so the widget layer can pick the
/// locale-appropriate name at render time, same separation `cityLabel`
/// already establishes between pure data and locale-aware display.
class CityRow {
  const CityRow({required this.city, this.governorate});

  final CityOption city;
  final GovernorateOption? governorate;
}

/// Joins [cities] with [governorates] client-side — same pure,
/// Firebase-free join pattern as `buildDriverRows`/`buildProductRows`. A
/// city's `governorateId` that doesn't match any loaded governorate (stale
/// reference, or a governorate that's since been "disabled" — governorates
/// are never deleted, only disabled, so this really only covers a genuinely
/// missing id) resolves to `governorate: null` rather than throwing.
/// Disabled governorates are still resolved by name (only excluded from
/// *picker* visibility, via [visibleGovernorates], not from this join).
List<CityRow> buildCityRows(List<CityOption> cities, List<GovernorateOption> governorates) {
  final governoratesById = {for (final governorate in governorates) governorate.id: governorate};
  return cities
      .map((city) => CityRow(city: city, governorate: governoratesById[city.governorateId]))
      .toList();
}

/// How many vendors currently have `city == cityId` — used to warn before
/// disabling a city (see AdminLocationsScreen's Switch handlers). Reuses
/// the vendor list AdminVendorsScreen's `allVendorsProvider` already
/// fetches, rather than issuing a new count query.
int vendorCountForCity(List<Vendor> vendors, String cityId) {
  return vendors.where((vendor) => vendor.city == cityId).length;
}

/// How many vendors currently sit in any city assigned to [governorateId] —
/// one join deeper than [vendorCountForCity] (vendors don't carry a
/// governorate directly, only a city). Pure, same reasoning.
int vendorCountForGovernorate(
  List<Vendor> vendors,
  List<CityOption> cities,
  String governorateId,
) {
  final cityIdsInGovernorate = cities
      .where((city) => city.governorateId == governorateId)
      .map((city) => city.id)
      .toSet();
  return vendors.where((vendor) => cityIdsInGovernorate.contains(vendor.city)).length;
}

final _idPattern = RegExp(r'^[a-z][a-z0-9_]*$');

/// Validation outcome for a governorate/city id field — a pure enum rather
/// than a localized string, so [validateLocationId] itself stays
/// Firebase/BuildContext-free and directly unit-testable; the form's
/// `validator:` closure maps this to the right l10n message.
enum LocationIdValidationError { required, invalidFormat, duplicate }

/// Shared id validation for both the Governorate and City add/edit forms:
/// required, lowercase/underscore slug pattern, and — only when adding a
/// new record ([isNew]) — must not collide with [existingIds] (the ids
/// currently loaded client-side at the moment the form was opened; the
/// real, race-safe guard against a collision Firestore itself sees is
/// FirestoreService.addGovernorate/addCity's transaction — see
/// governorates.rules.test.ts's comment for why this can't be done at the
/// rules layer alone). Editing an existing record never checks for a
/// collision against its own id.
LocationIdValidationError? validateLocationId(
  String? value, {
  required bool isNew,
  required Set<String> existingIds,
}) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return LocationIdValidationError.required;
  if (!_idPattern.hasMatch(trimmed)) return LocationIdValidationError.invalidFormat;
  if (isNew && existingIds.contains(trimmed)) return LocationIdValidationError.duplicate;
  return null;
}

/// Admin Locations — Governorates and Cities administration (Locations
/// Phase 4 UI, on top of the Phase 1–3 data foundation). Two tabs inside
/// one AdminScaffold-hosted screen, since `AdminDestination` has a single
/// `locations` entry (see admin_scaffold.dart) and the Cities tab's forms
/// need live governorate data anyway. No Districts/Service Areas/Maps/GPS/
/// routing/ETA/delivery-fee here — out of scope for this phase.
class AdminLocationsScreen extends StatelessWidget {
  const AdminLocationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DefaultTabController(
      length: 2,
      child: AdminScaffold(
        title: l10n.adminLocationsTitle,
        selected: AdminDestination.locations,
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TabBar(
              labelColor: VendorPalette.primaryCyan,
              unselectedLabelColor: VendorPalette.textSecondary,
              indicatorColor: VendorPalette.primaryCyan,
              tabs: [
                Tab(text: l10n.governoratesTabLabel),
                Tab(text: l10n.citiesTabLabel),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Expanded(
              child: TabBarView(
                children: [_GovernoratesTab(), _CitiesTab()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared search-field-plus-add-button row — AdminScaffold has no
/// floatingActionButton slot (it isn't its own Scaffold subclass call site,
/// see admin_scaffold.dart), so "Add" sits inline next to search instead,
/// same row every other admin list screen already opens with.
class _SearchRow extends StatelessWidget {
  const _SearchRow({
    required this.hintText,
    required this.addTooltip,
    required this.onChanged,
    required this.onAdd,
  });

  final String hintText;
  final String addTooltip;
  final ValueChanged<String> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: hintText,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              filled: true,
              fillColor: VendorPalette.surfaceContainer,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        IconButton.filled(
          icon: const Icon(Icons.add),
          tooltip: addTooltip,
          onPressed: onAdd,
        ),
      ],
    );
  }
}

class _GovernoratesTab extends ConsumerStatefulWidget {
  const _GovernoratesTab();

  @override
  ConsumerState<_GovernoratesTab> createState() => _GovernoratesTabState();
}

class _GovernoratesTabState extends ConsumerState<_GovernoratesTab>
    with AutomaticKeepAliveClientMixin {
  String _query = '';

  @override
  bool get wantKeepAlive => true;

  Future<void> _openForm({GovernorateOption? existing}) {
    final existingIds = (ref.read(allGovernoratesProvider).valueOrNull ?? const [])
        .map((g) => g.id)
        .toSet();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _GovernorateForm(existing: existing, existingIds: existingIds),
      ),
    );
  }

  Future<void> _setEnabled(GovernorateOption governorate, bool enabled) async {
    if (enabled) {
      HapticFeedback.selectionClick();
      await ref.read(firestoreServiceProvider).setGovernorateEnabled(governorate.id, enabled);
      return;
    }
    final vendors = ref.read(allVendorsProvider).valueOrNull ?? const <Vendor>[];
    final cities = ref.read(allCitiesProvider).valueOrNull ?? const <CityOption>[];
    final affected = vendorCountForGovernorate(vendors, cities, governorate.id);
    if (affected > 0) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showConfirmDialog(
        context,
        message: l10n.disableLocationInUseWarning(affected),
      );
      if (confirmed != true) return;
    }
    HapticFeedback.selectionClick();
    await ref.read(firestoreServiceProvider).setGovernorateEnabled(governorate.id, false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final governoratesAsync = ref.watch(allGovernoratesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchRow(
          hintText: l10n.searchGovernoratesHint,
          addTooltip: l10n.addGovernorateTitle,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          onAdd: () => _openForm(),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: governoratesAsync.animatedWhen(
            data: (governorates) {
              final filtered = _query.isEmpty
                  ? governorates
                  : governorates
                      .where((g) =>
                          g.nameEn.toLowerCase().contains(_query) || g.nameAr.contains(_query))
                      .toList();
              if (filtered.isEmpty) {
                return Center(child: Text(l10n.noGovernoratesFoundMessage));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final governorate = filtered[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        governorateLabel(context, governorate),
                        style: governorate.enabled
                            ? null
                            : TextStyle(color: Theme.of(context).disabledColor),
                      ),
                      subtitle: Text('#${governorate.order}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: governorate.enabled,
                            onChanged: (value) => _setEnabled(governorate, value),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: l10n.editTooltip,
                            onPressed: () => _openForm(existing: governorate),
                          ),
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
    );
  }
}

class _CitiesTab extends ConsumerStatefulWidget {
  const _CitiesTab();

  @override
  ConsumerState<_CitiesTab> createState() => _CitiesTabState();
}

class _CitiesTabState extends ConsumerState<_CitiesTab> with AutomaticKeepAliveClientMixin {
  String _query = '';
  String? _governorateFilter;

  @override
  bool get wantKeepAlive => true;

  Future<void> _openForm({CityOption? existing}) {
    final existingIds =
        (ref.read(allCitiesProvider).valueOrNull ?? const []).map((c) => c.id).toSet();
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _CityForm(existing: existing, existingIds: existingIds),
      ),
    );
  }

  Future<void> _setEnabled(CityOption city, bool enabled) async {
    if (enabled) {
      HapticFeedback.selectionClick();
      await ref.read(firestoreServiceProvider).setCityEnabled(city.id, enabled);
      return;
    }
    final vendors = ref.read(allVendorsProvider).valueOrNull ?? const <Vendor>[];
    final affected = vendorCountForCity(vendors, city.id);
    if (affected > 0) {
      final l10n = AppLocalizations.of(context)!;
      final confirmed = await showConfirmDialog(
        context,
        message: l10n.disableLocationInUseWarning(affected),
      );
      if (confirmed != true) return;
    }
    HapticFeedback.selectionClick();
    await ref.read(firestoreServiceProvider).setCityEnabled(city.id, false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = AppLocalizations.of(context)!;
    final citiesAsync = ref.watch(allCitiesProvider);
    final governorates = ref.watch(allGovernoratesProvider).valueOrNull ?? const <GovernorateOption>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SearchRow(
          hintText: l10n.searchCitiesHint,
          addTooltip: l10n.addCityTitle,
          onChanged: (value) => setState(() => _query = value.trim().toLowerCase()),
          onAdd: () => _openForm(),
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
                  selected: _governorateFilter == null,
                  onSelected: (_) => setState(() => _governorateFilter = null),
                ),
              ),
              for (final governorate in governorates)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(governorateLabel(context, governorate)),
                    selected: _governorateFilter == governorate.id,
                    onSelected: (_) => setState(() => _governorateFilter = governorate.id),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: citiesAsync.animatedWhen(
            data: (cities) {
              final rows = buildCityRows(cities, governorates);
              final filtered = rows.where((row) {
                final matchesQuery = _query.isEmpty ||
                    row.city.nameEn.toLowerCase().contains(_query) ||
                    row.city.nameAr.contains(_query);
                final matchesGovernorate =
                    _governorateFilter == null || row.city.governorateId == _governorateFilter;
                return matchesQuery && matchesGovernorate;
              }).toList();
              if (filtered.isEmpty) {
                return Center(child: Text(l10n.noCitiesFoundMessage));
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: filtered.length,
                itemBuilder: (context, index) {
                  final row = filtered[index];
                  return Card(
                    child: ListTile(
                      title: Text(
                        cityLabel(context, row.city.id, cities),
                        style: row.city.enabled
                            ? null
                            : TextStyle(color: Theme.of(context).disabledColor),
                      ),
                      subtitle: Text(
                        '${governorateLabel(context, row.governorate)} · #${row.city.order}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            value: row.city.enabled,
                            onChanged: (value) => _setEnabled(row.city, value),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            tooltip: l10n.editTooltip,
                            onPressed: () => _openForm(existing: row.city),
                          ),
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
    );
  }
}

class _GovernorateForm extends ConsumerStatefulWidget {
  const _GovernorateForm({this.existing, required this.existingIds});

  final GovernorateOption? existing;
  final Set<String> existingIds;

  @override
  ConsumerState<_GovernorateForm> createState() => _GovernorateFormState();
}

class _GovernorateFormState extends ConsumerState<_GovernorateForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idController;
  late final TextEditingController _nameEnController;
  late final TextEditingController _nameArController;
  late final TextEditingController _orderController;
  late bool _enabled;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idController = TextEditingController(text: existing?.id ?? '');
    _nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    _nameArController = TextEditingController(text: existing?.nameAr ?? '');
    _orderController = TextEditingController(text: (existing?.order ?? 0).toString());
    _enabled = existing?.enabled ?? true;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameEnController.dispose();
    _nameArController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  String? _validateId(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final error = validateLocationId(
      value,
      isNew: widget.existing == null,
      existingIds: widget.existingIds,
    );
    return switch (error) {
      null => null,
      LocationIdValidationError.required => l10n.requiredFieldError,
      LocationIdValidationError.invalidFormat => l10n.invalidIdError,
      LocationIdValidationError.duplicate => l10n.duplicateIdError,
    };
  }

  String? _validateRequired(String? value) {
    final l10n = AppLocalizations.of(context)!;
    return (value?.trim().isEmpty ?? true) ? l10n.requiredFieldError : null;
  }

  String? _validateOrder(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(value?.trim() ?? '');
    return (parsed == null || parsed < 0) ? l10n.invalidOrderError : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final governorate = GovernorateOption(
        id: widget.existing?.id ?? _idController.text.trim(),
        nameEn: _nameEnController.text.trim(),
        nameAr: _nameArController.text.trim(),
        enabled: _enabled,
        order: int.parse(_orderController.text.trim()),
      );
      final firestore = ref.read(firestoreServiceProvider);
      if (widget.existing == null) {
        await firestore.addGovernorate(governorate);
      } else {
        await firestore.updateGovernorate(governorate);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNew = widget.existing == null;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isNew ? l10n.addGovernorateTitle : l10n.editGovernorateTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                enabled: isNew,
                decoration: InputDecoration(labelText: l10n.locationIdFieldLabel),
                validator: _validateId,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameEnController,
                decoration: InputDecoration(labelText: l10n.nameEnFieldLabel),
                validator: _validateRequired,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameArController,
                decoration: InputDecoration(labelText: l10n.nameArFieldLabel),
                validator: _validateRequired,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _orderController,
                decoration: InputDecoration(labelText: l10n.locationOrderFieldLabel),
                keyboardType: TextInputType.number,
                validator: _validateOrder,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.locationEnabledLabel),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 12),
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
      ),
    );
  }
}

class _CityForm extends ConsumerStatefulWidget {
  const _CityForm({this.existing, required this.existingIds});

  final CityOption? existing;
  final Set<String> existingIds;

  @override
  ConsumerState<_CityForm> createState() => _CityFormState();
}

class _CityFormState extends ConsumerState<_CityForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _idController;
  late final TextEditingController _nameEnController;
  late final TextEditingController _nameArController;
  late final TextEditingController _orderController;
  late bool _enabled;
  String? _governorateId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _idController = TextEditingController(text: existing?.id ?? '');
    _nameEnController = TextEditingController(text: existing?.nameEn ?? '');
    _nameArController = TextEditingController(text: existing?.nameAr ?? '');
    _orderController = TextEditingController(text: (existing?.order ?? 0).toString());
    _enabled = existing?.enabled ?? true;
    _governorateId = existing?.governorateId;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameEnController.dispose();
    _nameArController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  String? _validateId(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final error = validateLocationId(
      value,
      isNew: widget.existing == null,
      existingIds: widget.existingIds,
    );
    return switch (error) {
      null => null,
      LocationIdValidationError.required => l10n.requiredFieldError,
      LocationIdValidationError.invalidFormat => l10n.invalidIdError,
      LocationIdValidationError.duplicate => l10n.duplicateIdError,
    };
  }

  String? _validateRequired(String? value) {
    final l10n = AppLocalizations.of(context)!;
    return (value?.trim().isEmpty ?? true) ? l10n.requiredFieldError : null;
  }

  String? _validateOrder(String? value) {
    final l10n = AppLocalizations.of(context)!;
    final parsed = int.tryParse(value?.trim() ?? '');
    return (parsed == null || parsed < 0) ? l10n.invalidOrderError : null;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final city = CityOption(
        id: widget.existing?.id ?? _idController.text.trim(),
        nameEn: _nameEnController.text.trim(),
        nameAr: _nameArController.text.trim(),
        enabled: _enabled,
        order: int.parse(_orderController.text.trim()),
        governorateId: _governorateId,
      );
      final firestore = ref.read(firestoreServiceProvider);
      if (widget.existing == null) {
        await firestore.addCity(city);
      } else {
        await firestore.updateCity(city);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isNew = widget.existing == null;
    final liveGovernorates =
        ref.watch(allGovernoratesProvider).valueOrNull ?? const <GovernorateOption>[];
    final governoratesById = {for (final g in liveGovernorates) g.id: g};
    // Enabled governorates, plus the city's current governorate forced in
    // even if it's disabled or missing from the live list — exact same
    // "never silently reassign" rule the existing city dropdown already
    // follows for vendors (see vendor_dashboard_screen.dart).
    final selectableIds = visibleGovernorates(liveGovernorates).map((g) => g.id).toList();
    if (_governorateId != null && !selectableIds.contains(_governorateId)) {
      selectableIds.add(_governorateId!);
    }

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isNew ? l10n.addCityTitle : l10n.editCityTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idController,
                enabled: isNew,
                decoration: InputDecoration(labelText: l10n.locationIdFieldLabel),
                validator: _validateId,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameEnController,
                decoration: InputDecoration(labelText: l10n.nameEnFieldLabel),
                validator: _validateRequired,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _nameArController,
                decoration: InputDecoration(labelText: l10n.nameArFieldLabel),
                validator: _validateRequired,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _governorateId,
                decoration: InputDecoration(labelText: l10n.governorateAssignmentFieldLabel),
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text(l10n.governorateUnassignedLabel),
                  ),
                  for (final id in selectableIds)
                    DropdownMenuItem<String?>(
                      value: id,
                      child: Text(governorateLabel(context, governoratesById[id])),
                    ),
                ],
                onChanged: (value) => setState(() => _governorateId = value),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _orderController,
                decoration: InputDecoration(labelText: l10n.locationOrderFieldLabel),
                keyboardType: TextInputType.number,
                validator: _validateOrder,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.locationEnabledLabel),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              const SizedBox(height: 12),
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
      ),
    );
  }
}
