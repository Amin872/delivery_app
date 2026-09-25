import 'dart:math' as math;

import '../../models/coordinates.dart';

const double _earthRadiusMeters = 6371000;

/// Straight-line ("as the crow flies") distance between [a] and [b] in
/// meters, via the haversine formula — pure Dart, no new dependency and no
/// routing/directions API call. This is deliberately NOT a road-network
/// distance: no routing service is wired into this app (see
/// services/geocoding_service.dart's own architectural-boundary note on
/// what Mapbox is/isn't used for yet) — a real road-distance/ETA would need
/// a Directions API call per update, which is a real cost/complexity a
/// straight-line estimate avoids for a first version. See
/// [estimateEtaMinutes] for how this is turned into a rough ETA.
double haversineDistanceMeters(Coordinates a, Coordinates b) {
  final lat1 = a.latitude * math.pi / 180;
  final lat2 = b.latitude * math.pi / 180;
  final dLat = (b.latitude - a.latitude) * math.pi / 180;
  final dLon = (b.longitude - a.longitude) * math.pi / 180;

  final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
  final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  return _earthRadiusMeters * c;
}

// Assumed average urban delivery speed (city-street driving/riding, with
// stops) — used only to turn a straight-line distance into a rough ETA
// range when no real routing data is available. Deliberately conservative
// (city traffic, not open-road speed) so the estimate skews toward "won't
// arrive later than this" rather than promising an optimistic time.
const double _assumedAverageSpeedKmh = 25;

/// Rough ETA in minutes for covering [distanceMeters] at
/// [_assumedAverageSpeedKmh] — an estimate, not a routed prediction (see
/// [haversineDistanceMeters]'s own note on why no routing API is used).
/// Callers should label this as approximate wherever it's shown (see
/// `etaLabel`'s "~" prefix in the ARB strings).
int estimateEtaMinutes(double distanceMeters) {
  final distanceKm = distanceMeters / 1000;
  final hours = distanceKm / _assumedAverageSpeedKmh;
  final minutes = (hours * 60).round();
  return minutes < 1 ? 1 : minutes;
}

/// Straight-line distance plus the rough ETA for it, as one value — what
/// both the customer's tracking map and the driver's active-delivery card
/// show. Always an approximation: straight line, assumed average speed, no
/// routing or traffic.
class TripEstimate {
  const TripEstimate({required this.distanceMeters, required this.etaMinutes});

  final double distanceMeters;
  final int etaMinutes;

  /// Distance in kilometres with one decimal, '.'-separated regardless of
  /// locale (e.g. "2.4"), for the "≈ {distance} km" style labels.
  String get distanceKmLabel => (distanceMeters / 1000).toStringAsFixed(1);
}

/// [haversineDistanceMeters] from [from] to [to] and [estimateEtaMinutes]
/// for it, or null when either point is unknown — callers hide the estimate
/// rather than show a made-up one.
TripEstimate? estimateTrip(Coordinates? from, Coordinates? to) {
  if (from == null || to == null) return null;
  final meters = haversineDistanceMeters(from, to);
  return TripEstimate(distanceMeters: meters, etaMinutes: estimateEtaMinutes(meters));
}
