import '../../models/city.dart';
import '../../models/district.dart';
import '../../models/governorate.dart';
import '../../services/geocoding_service.dart' show GeocodeResult;

// Pure, Firebase/Mapbox-independent reconciliation layer between an
// external geocoding signal (GeocodeResult) and our own Firestore location
// hierarchy (GovernorateOption/CityOption/DistrictOption) — see the
// Location/Maps Architecture audit. Firestore's nameAr/nameEn remain the
// ONLY authoritative display names; a GeocodeResult's country/region/
// city/district/neighborhood strings are external signal used purely to
// find which existing Firestore document (if any) a coordinate/address
// corresponds to. Nothing in this file writes to Firestore, calls Mapbox,
// or mutates a Vendor/DeliveryAddress/user profile — matching is the only
// concern here; deciding what to do with a match (e.g. writing a
// districtId somewhere) is a separate, later, caller-side concern.
//
// No hardcoded Syrian (or any other) place name appears anywhere in this
// file — every candidate name comes from the GovernorateOption/CityOption/
// DistrictOption lists passed in by the caller.

// ---------------------------------------------------------------------------
// Normalization
// ---------------------------------------------------------------------------

// Arabic tashkeel (diacritics): fatha/damma/kasra/shadda/sukun and related
// combining marks (U+064B-U+065F), the superscript alef (U+0670), and the
// small Quranic annotation marks (U+06D6-U+06ED). Stripping these is a
// standard, well-established Arabic text-normalization step — NOT a
// translation and NOT a guess: the same word written with and without
// optional diacritical marks is still the same word.
final RegExp _arabicDiacritics = RegExp('[ً-ٰٟۖ-ۭ]');

// Arabic tatweel/kashida (ـ, U+0640) — a purely typographic elongation
// character with no semantic meaning; stripping it doesn't change the word.
final RegExp _arabicTatweel = RegExp('ـ');

// Punctuation (Latin and Arabic) normalized to a plain space rather than
// removed outright, so "Al-Mazzeh" and "Al Mazzeh" normalize to the same
// two-word form instead of accidentally merging into one word. Includes
// Arabic comma/semicolon/question mark (U+060C, U+061B, U+061F) alongside
// their Latin equivalents.
final RegExp _punctuationToSpace = RegExp(
  '[.,;:!?\'"`‘’“”،؛؟\\-_/\\\\()\\[\\]{}]',
);

final RegExp _repeatedWhitespace = RegExp(r'\s+');

/// Normalizes [input] for name-matching purposes: strips Arabic
/// diacritics/tatweel, normalizes punctuation to whitespace, case-folds
/// Latin text (a no-op on Arabic script, which has no case), collapses
/// repeated whitespace, and trims. Deliberately does NOT translate,
/// transliterate, or fold Arabic letter-shape variants (e.g. alef-hamza
/// forms, taa marbuta vs haa) — only the safe, script-agnostic variations
/// explicitly called out in the Location/Maps Architecture audit.
/// A string in one script will never normalize to the same value as a
/// string in another script, so this can never produce a cross-language
/// false-positive match on its own.
String normalizeLocationName(String input) {
  var result = input;
  result = result.replaceAll(_arabicDiacritics, '');
  result = result.replaceAll(_arabicTatweel, '');
  result = result.replaceAll(_punctuationToSpace, ' ');
  result = result.toLowerCase();
  result = result.replaceAll(_repeatedWhitespace, ' ');
  return result.trim();
}

// ---------------------------------------------------------------------------
// Match result
// ---------------------------------------------------------------------------

/// How confident [matchLocation] is in the location it resolved — a small,
/// explicit vocabulary rather than an arbitrary numeric score (the product/
/// UI layer should never need to interpret a raw confidence number).
enum MatchConfidence {
  /// A city-level exact name match, corroborated by a district-level exact
  /// match under that same city (or a governorate-level match, when no
  /// district signal was available — see [matchLocation]'s implementation).
  exact,

  /// A city-level exact name match with no additional corroborating
  /// evidence (no district signal present, or a district signal present
  /// but not resolved under the matched city).
  strong,

  /// Only weak or partial evidence — e.g. a governorate-level match with
  /// no city match, or an ambiguous match where multiple candidates tied
  /// and no single one was chosen.
  possible,

  /// No usable evidence matched anything in the supplied candidate lists.
  none,
}

/// The result of reconciling a [GeocodeResult] against our own Firestore
/// location hierarchy. Each level is independently nullable — a caller
/// should never assume [city] is set just because [district] is, or vice
/// versa (though [matchLocation] never returns a [district] whose
/// `cityId` doesn't match [city]'s own id — see its own documentation).
/// [reasons] is a diagnostic, non-localized trail of what evidence was
/// used or why a level was left unmatched — for logging/debugging, not
/// for direct display to a user.
class LocationMatchResult {
  final GovernorateOption? governorate;
  final CityOption? city;
  final DistrictOption? district;
  final MatchConfidence confidence;
  final List<String> reasons;

  const LocationMatchResult({
    this.governorate,
    this.city,
    this.district,
    required this.confidence,
    required this.reasons,
  });

  /// Convenience constant for "nothing matched, no evidence at all" —
  /// equivalent to what [matchLocation] itself returns for an empty/blank
  /// [GeocodeResult], but usable directly by callers that need a neutral
  /// starting value.
  static const none = LocationMatchResult(confidence: MatchConfidence.none, reasons: []);
}

// ---------------------------------------------------------------------------
// Matching
// ---------------------------------------------------------------------------

/// Reconciles [geocodeResult] against the currently-loaded
/// [governorates]/[cities]/[districts] lists and returns the best
/// deterministic match — see the file-level documentation for the overall
/// architectural boundary this respects.
///
/// Matching priority (strongest evidence first — see the Location/Maps
/// Architecture audit's own priority ordering):
///  1. Exact normalized match against a candidate's `nameAr`.
///  2. Exact normalized match against a candidate's `nameEn`.
///     (`GeocodeResult`'s city/district/region fields are single,
///     already-resolved strings with no separate language tag — comparing
///     the same normalized string against both `nameAr` and `nameEn`
///     achieves priorities 1 and 2 together without needing to know in
///     advance which script the provider returned, since a string in one
///     script can never normalize-equal a name in the other script.)
///  3. Multiple corroborating signals (a matched city AND a matched
///     district under that city) elevate confidence from `strong` to
///     `exact`, rather than being used to find a match on their own.
///  4. Fuzzy/partial text matching is deliberately NOT implemented — the
///     audit explicitly forbids it ("do not perform fuzzy matching that
///     could silently map one Syrian city to another"), so there is no
///     weaker tier beyond exact normalized matching.
///
/// Hierarchy rules enforced:
///  - A city candidate is excluded only when it HAS a `governorateId` that
///    conflicts with an already-matched governorate; a city with
///    `governorateId == null`, or one matching the governorate, is always
///    a valid candidate (see [CityOption.governorateId]'s own nullability).
///  - A district is only ever matched against districts whose `cityId`
///    equals the already-matched city's id — never independently.
///  - If governorate/city name matching is ambiguous (more than one
///    candidate normalizes to the same text), that level is left
///    unmatched (null) rather than guessing, and the ambiguity is recorded
///    in [LocationMatchResult.reasons].
///  - Disabled candidates are never filtered out of the input lists by
///    this function — "disabled" means "not offered for new selection",
///    not "doesn't exist"; filtering by `enabled` (if desired) is the
///    caller's decision, made on the already-returned match.
LocationMatchResult matchLocation({
  required GeocodeResult geocodeResult,
  required List<GovernorateOption> governorates,
  required List<CityOption> cities,
  required List<DistrictOption> districts,
}) {
  final reasons = <String>[];

  final governorateMatch = _matchByName<GovernorateOption>(
    text: geocodeResult.region,
    candidates: governorates,
    nameAr: (g) => g.nameAr,
    nameEn: (g) => g.nameEn,
    levelLabel: 'governorate',
    reasons: reasons,
  );

  // A city with no governorateId yet is always a valid candidate — only
  // exclude a city whose KNOWN governorateId conflicts with what we
  // matched from the region text.
  final cityCandidates = governorateMatch == null
      ? cities
      : cities
          .where((city) => city.governorateId == null || city.governorateId == governorateMatch.id)
          .toList();

  final cityMatch = _matchByName<CityOption>(
    text: geocodeResult.city,
    candidates: cityCandidates,
    nameAr: (c) => c.nameAr,
    nameEn: (c) => c.nameEn,
    levelLabel: 'city',
    reasons: reasons,
  );

  DistrictOption? districtMatch;
  if (cityMatch != null) {
    final districtCandidates = districts.where((d) => d.cityId == cityMatch.id).toList();
    districtMatch = _matchByName<DistrictOption>(
      text: geocodeResult.district,
      candidates: districtCandidates,
      nameAr: (d) => d.nameAr,
      nameEn: (d) => d.nameEn,
      levelLabel: 'district',
      reasons: reasons,
    );
  } else if (geocodeResult.district != null && geocodeResult.district!.trim().isNotEmpty) {
    reasons.add('district: skipped — no matched city to validate "${geocodeResult.district}" against');
  }

  final confidence = _confidenceFor(
    cityMatch: cityMatch,
    governorateMatch: governorateMatch,
    districtInputPresent:
        geocodeResult.district != null && geocodeResult.district!.trim().isNotEmpty,
    districtMatch: districtMatch,
    reasons: reasons,
  );

  return LocationMatchResult(
    governorate: governorateMatch,
    city: cityMatch,
    district: districtMatch,
    confidence: confidence,
    reasons: List.unmodifiable(reasons),
  );
}

/// Exact-normalized-name lookup among [candidates] — returns the single
/// candidate whose `nameAr` or `nameEn` normalizes to the same value as
/// [text], or null if there's no match or more than one (ambiguous).
/// Ambiguity and no-match are both recorded in [reasons] but are NOT
/// distinguished by return value alone (both return null) — the caller
/// inspects [reasons] for the specific "ambiguous" wording where the
/// distinction matters (see [_confidenceFor]).
T? _matchByName<T>({
  required String? text,
  required List<T> candidates,
  required String Function(T) nameAr,
  required String Function(T) nameEn,
  required String levelLabel,
  required List<String> reasons,
}) {
  if (text == null || text.trim().isEmpty) return null;

  final normalizedText = normalizeLocationName(text);
  if (normalizedText.isEmpty) return null;

  final matches = <T>[];
  final matchedField = <T, String>{};
  for (final candidate in candidates) {
    if (normalizeLocationName(nameAr(candidate)) == normalizedText) {
      matches.add(candidate);
      matchedField[candidate] = 'nameAr';
    } else if (normalizeLocationName(nameEn(candidate)) == normalizedText) {
      matches.add(candidate);
      matchedField[candidate] = 'nameEn';
    }
  }

  if (matches.isEmpty) {
    reasons.add('$levelLabel: no exact name match for "$text"');
    return null;
  }
  if (matches.length > 1) {
    reasons.add(
      '$levelLabel: ambiguous — "$text" matched ${matches.length} candidates, no single selection made',
    );
    return null;
  }

  final matched = matches.single;
  reasons.add('$levelLabel: exact match via ${matchedField[matched]} for "$text"');
  return matched;
}

MatchConfidence _confidenceFor({
  required CityOption? cityMatch,
  required GovernorateOption? governorateMatch,
  required bool districtInputPresent,
  required DistrictOption? districtMatch,
  required List<String> reasons,
}) {
  if (cityMatch == null) {
    if (governorateMatch != null) {
      reasons.add('overall: possible — only governorate-level evidence available');
      return MatchConfidence.possible;
    }
    if (reasons.any((r) => r.contains('ambiguous'))) {
      reasons.add('overall: possible — ambiguous candidate(s), no confident selection');
      return MatchConfidence.possible;
    }
    reasons.add('overall: none — no location evidence matched');
    return MatchConfidence.none;
  }

  if (districtInputPresent && districtMatch != null) {
    reasons.add('overall: exact — city and district evidence corroborate each other');
    return MatchConfidence.exact;
  }

  reasons.add('overall: strong — city matched exactly, no corroborating district evidence');
  return MatchConfidence.strong;
}
