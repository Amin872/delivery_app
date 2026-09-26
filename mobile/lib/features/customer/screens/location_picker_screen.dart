import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/coordinates.dart';
import '../../../services/geocoding_service.dart';
import '../../../services/location_service.dart';

final _locationServiceProvider = Provider<LocationService>((ref) => LocationService());

/// Result of [LocationPickerScreen] — the confirmed pin coordinates plus
/// whatever reverse-geocoding signal was available for it at confirm time.
/// [geocodeResult] is purely advisory (see services/geocoding_service.dart's
/// architectural-boundary note) — the caller (EditAddressScreen) is
/// responsible for reconciling it against the app's own governorate/city/
/// neighbourhood lists via `core/location/location_matcher.dart`, and for
/// letting the customer override whatever it suggests. Null when reverse
/// geocoding failed or wasn't configured (see MapboxGeocodingService's
/// 'missing-token' case) — the customer can still confirm a bare pin with
/// no auto-detected address text.
class LocationPickResult {
  const LocationPickResult({required this.coordinates, this.geocodeResult});

  final Coordinates coordinates;
  final GeocodeResult? geocodeResult;
}

// Default camera position when no current-location fix and no existing
// address are available — central Damascus, this app's original/primary
// city (see models/city.dart's legacyCityIds). Just a starting viewport,
// never written anywhere as a real address.
const _fallbackCenter = LatLng(33.5138, 36.2765);

/// Map-first location picker (Phase 4 requirement #7): current-location
/// button, pan-to-move-the-pin (a fixed center pin with the map panning
/// underneath it — the same interaction Careem/Uber-style pickers use,
/// avoiding a draggable-marker's extra hit-testing complexity for the same
/// result), place search (Mapbox forward geocoding), and a confirm step.
/// Returns a [LocationPickResult] via `Navigator.pop`, or null if the
/// customer backs out without confirming.
class LocationPickerScreen extends ConsumerStatefulWidget {
  const LocationPickerScreen({this.initialCoordinates, super.key});

  /// Pre-fills the map center when editing an existing SavedAddress that
  /// already has a pin — null opens on [_fallbackCenter] instead.
  final Coordinates? initialCoordinates;

  @override
  ConsumerState<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends ConsumerState<LocationPickerScreen> {
  GoogleMapController? _controller;
  late LatLng _center = widget.initialCoordinates != null
      ? LatLng(widget.initialCoordinates!.latitude, widget.initialCoordinates!.longitude)
      : _fallbackCenter;
  GeocodeResult? _geocodeResult;
  bool _isReverseGeocoding = false;
  bool _isLocating = false;
  bool _isSearching = false;
  List<PlaceMatch> _searchResults = [];
  final _searchController = TextEditingController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Resolve an initial address label for a pre-filled pin (edit flow) —
    // a fresh/fallback-centered picker waits for the first camera move
    // instead, so it doesn't reverse-geocode central Damascus by default.
    if (widget.initialCoordinates != null) _reverseGeocode(_center);
  }

  @override
  void dispose() {
    _controller?.dispose();
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _reverseGeocode(LatLng target) async {
    setState(() => _isReverseGeocoding = true);
    try {
      final result = await ref.read(geocodingServiceProvider).reverseGeocode(
            Coordinates(latitude: target.latitude, longitude: target.longitude),
          );
      if (mounted && target == _center) setState(() => _geocodeResult = result);
    } catch (_) {
      // Best-effort — a failed reverse geocode just leaves _geocodeResult
      // as-is (null, or the previous pin's result); the customer can still
      // confirm a bare pin either way, see LocationPickResult's doc comment.
      if (mounted) setState(() => _geocodeResult = null);
    } finally {
      if (mounted) setState(() => _isReverseGeocoding = false);
    }
  }

  void _onCameraIdle() {
    _debounce?.cancel();
    // Debounced rather than firing immediately — onCameraIdle can fire in a
    // quick sequence during a fling/zoom gesture; only the final resting
    // position is worth a network call.
    _debounce = Timer(const Duration(milliseconds: 400), () => _reverseGeocode(_center));
  }

  Future<void> _useCurrentLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await ref.read(_locationServiceProvider).getCurrentPosition();
      final target = LatLng(position.latitude, position.longitude);
      await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
      if (mounted) setState(() => _center = target);
      await _reverseGeocode(target);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(localizedErrorMessage(context, error)),
        ));
      }
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() => _searchResults = []);
      return;
    }
    setState(() => _isSearching = true);
    try {
      final results = await ref.read(geocodingServiceProvider).forwardGeocode(query);
      if (mounted) setState(() => _searchResults = results);
    } catch (_) {
      if (mounted) setState(() => _searchResults = []);
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _selectSearchResult(PlaceMatch match) async {
    final target = LatLng(match.coordinates.latitude, match.coordinates.longitude);
    setState(() {
      _searchResults = [];
      _searchController.clear();
    });
    FocusScope.of(context).unfocus();
    await _controller?.animateCamera(CameraUpdate.newLatLngZoom(target, 16));
    setState(() => _center = target);
    await _reverseGeocode(target);
  }

  void _confirm() {
    Navigator.of(context).pop(LocationPickResult(
      coordinates: Coordinates(latitude: _center.latitude, longitude: _center.longitude),
      geocodeResult: _geocodeResult,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.locationPickerTitle),
        ),
        body: Stack(
          children: [
            GoogleMap(
              initialCameraPosition: CameraPosition(target: _center, zoom: 15),
              onMapCreated: (controller) => _controller = controller,
              onCameraMove: (position) => _center = position.target,
              onCameraIdle: _onCameraIdle,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
              style: Theme.of(context).brightness == Brightness.dark ? _darkMapStyle : null,
            ),
            const IgnorePointer(
              child: Center(
                child: Padding(
                  // Pin's own visual weight sits above its tip, so the tip
                  // (not the icon's geometric center) is what should align
                  // with the map's true center — offset up by half the
                  // icon's height.
                  padding: EdgeInsets.only(bottom: 36),
                  child: Icon(Icons.location_pin, size: 44, color: VendorPalette.primaryCyan),
                ),
              ),
            ),
            Positioned(
              top: AppSpacing.md,
              left: AppSpacing.md,
              right: AppSpacing.md,
              child: _SearchBar(
                controller: _searchController,
                isSearching: _isSearching,
                results: _searchResults,
                onChanged: (value) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 400), () => _search(value));
                },
                onSelect: _selectSearchResult,
              ),
            ),
            Positioned(
              right: AppSpacing.md,
              bottom: 140,
              child: FloatingActionButton(
                heroTag: 'use_current_location',
                backgroundColor: VendorPalette.surfaceContainer,
                foregroundColor: VendorPalette.primaryCyan,
                onPressed: _isLocating ? null : _useCurrentLocation,
                tooltip: l10n.useCurrentLocationButton,
                child: _isLocating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              left: AppSpacing.md,
              right: AppSpacing.md,
              bottom: AppSpacing.lg,
              child: _ConfirmBar(
                isResolving: _isReverseGeocoding,
                geocodeResult: _geocodeResult,
                onConfirm: _confirm,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.isSearching,
    required this.results,
    required this.onChanged,
    required this.onSelect,
  });

  final TextEditingController controller;
  final bool isSearching;
  final List<PlaceMatch> results;
  final ValueChanged<String> onChanged;
  final ValueChanged<PlaceMatch> onSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: VendorPalette.surfaceContainer,
            borderRadius: AppRadius.medium,
            boxShadow: [BoxShadow(color: AppPalette.shadow.withValues(alpha: 0.26), blurRadius: 8)],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(color: VendorPalette.textPrimary),
            decoration: InputDecoration(
              hintText: l10n.searchLocationHint,
              hintStyle: const TextStyle(color: VendorPalette.textMuted),
              prefixIcon: const Icon(Icons.search, color: VendorPalette.textSecondary),
              suffixIcon: isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              filled: true,
              fillColor: Colors.transparent,
              border: OutlineInputBorder(borderRadius: AppRadius.medium, borderSide: BorderSide.none),
            ),
          ),
        ),
        if (results.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: AppSpacing.xs),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: VendorPalette.surfaceContainer,
              borderRadius: AppRadius.medium,
              boxShadow: [BoxShadow(color: AppPalette.shadow.withValues(alpha: 0.26), blurRadius: 8)],
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: results.length,
              itemBuilder: (context, index) {
                final match = results[index];
                return ListTile(
                  leading: const Icon(Icons.place_outlined, color: VendorPalette.textSecondary),
                  title: Text(
                    match.name ?? match.formattedAddress ?? '',
                    style: const TextStyle(color: VendorPalette.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: match.formattedAddress != null && match.name != null
                      ? Text(
                          match.formattedAddress!,
                          style: const TextStyle(color: VendorPalette.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  onTap: () => onSelect(match),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _ConfirmBar extends StatelessWidget {
  const _ConfirmBar({
    required this.isResolving,
    required this.geocodeResult,
    required this.onConfirm,
  });

  final bool isResolving;
  final GeocodeResult? geocodeResult;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final summary = geocodeResult?.formattedAddress;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: VendorPalette.surfaceContainer,
        borderRadius: AppRadius.large,
        boxShadow: [BoxShadow(color: AppPalette.shadow.withValues(alpha: 0.38), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isResolving
                ? l10n.detectingLocationMessage
                : (summary ?? l10n.dragPinHint),
            style: const TextStyle(color: VendorPalette.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AppSpacing.sm),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const ValueKey('confirm_location_button'),
              onPressed: onConfirm,
              child: Text(l10n.confirmLocationButton),
            ),
          ),
        ],
      ),
    );
  }
}

// Same Google Maps "Night mode" style as DriverTrackingMap — kept as a
// separate literal here (rather than importing DriverTrackingMap's private
// one) since that constant is private to its own file.
const _darkMapStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#212121"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#757575"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#212121"}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#757575"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1b1b1b"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2c2c2c"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#000000"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#373737"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3c3c3c"}]},
  {"featureType": "transit", "elementType": "geometry", "stylers": [{"color": "#2f2f2f"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#000000"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3d3d3d"}]}
]
''';
