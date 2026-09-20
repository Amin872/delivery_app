import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/city.dart';
import '../../models/governorate.dart';
import '../../models/order.dart';
import '../../models/vendor.dart';

// Bundled fonts cover Arabic/Latin only (see AppTheme's font-family note) —
// languageCode is enough to tell the two apart, no need for a full Locale
// comparison.
bool _isArabic(BuildContext context) => Localizations.localeOf(context).languageCode == 'ar';

String orderStatusLabel(BuildContext context, OrderStatus status) {
  final l10n = AppLocalizations.of(context)!;
  switch (status) {
    case OrderStatus.pending:
      return l10n.orderStatusPending;
    case OrderStatus.accepted:
      return l10n.orderStatusAccepted;
    case OrderStatus.preparing:
      return l10n.orderStatusPreparing;
    case OrderStatus.readyForPickup:
      return l10n.orderStatusReadyForPickup;
    case OrderStatus.pickedUp:
      return l10n.orderStatusPickedUp;
    case OrderStatus.delivering:
      return l10n.orderStatusDelivering;
    case OrderStatus.delivered:
      return l10n.orderStatusDelivered;
    case OrderStatus.cancelled:
      return l10n.orderStatusCancelled;
  }
}

String vendorCategoryLabel(BuildContext context, VendorCategory category) {
  final l10n = AppLocalizations.of(context)!;
  switch (category) {
    case VendorCategory.groceries:
      return l10n.vendorCategoryGroceries;
    case VendorCategory.restaurants:
      return l10n.vendorCategoryRestaurants;
    case VendorCategory.bakery:
      return l10n.vendorCategoryBakery;
    case VendorCategory.drinks:
      return l10n.vendorCategoryDrinks;
    case VendorCategory.pharmacy:
      return l10n.vendorCategoryPharmacy;
  }
}

String vendorApprovalStatusLabel(BuildContext context, VendorApprovalStatus status) {
  final l10n = AppLocalizations.of(context)!;
  switch (status) {
    case VendorApprovalStatus.pending:
      return l10n.vendorStatusPending;
    case VendorApprovalStatus.approved:
      return l10n.vendorStatusApproved;
    case VendorApprovalStatus.rejected:
      return l10n.vendorStatusRejected;
  }
}

/// Display name for [cityId] — looks it up in [knownCities] (the live
/// `cities` collection, see `FirestoreService.watchCities()`) first, so an
/// admin-managed name change or a newly-added city shows up immediately.
/// Falls back to the five legacy ARB strings (`cityDamascus`..`cityTartus`)
/// for [legacyCityIds] when [knownCities] is empty/hasn't loaded/doesn't
/// contain [cityId] yet — so every vendor's city always renders as a real
/// name, never a blank or an exception, even before the live list is
/// available. An id that's neither in [knownCities] nor a legacy id (e.g.
/// stale/removed reference data) falls back to the raw id itself rather
/// than crashing.
String cityLabel(BuildContext context, String cityId, [List<CityOption> knownCities = const []]) {
  for (final city in knownCities) {
    if (city.id == cityId) {
      return _isArabic(context) ? city.nameAr : city.nameEn;
    }
  }
  return _legacyCityLabel(context, cityId);
}

String _legacyCityLabel(BuildContext context, String cityId) {
  final l10n = AppLocalizations.of(context)!;
  switch (cityId) {
    case 'damascus':
      return l10n.cityDamascus;
    case 'aleppo':
      return l10n.cityAleppo;
    case 'homs':
      return l10n.cityHoms;
    case 'latakia':
      return l10n.cityLatakia;
    case 'tartus':
      return l10n.cityTartus;
    default:
      return cityId;
  }
}

/// Display name for [governorate] — unlike [cityLabel], governorates have no
/// retired-enum/legacy-ARB era to fall back to (Locations Phase 3 was
/// Firestore-data-driven from day one), so this is just a locale pick, plus
/// an explicit "unassigned" label when [governorate] is null — covers both
/// a city with no governorateId and a governorateId that no longer resolves
/// against the currently-loaded list (stale/removed reference), so this
/// never crashes on a dangling reference.
String governorateLabel(BuildContext context, GovernorateOption? governorate) {
  if (governorate == null) {
    return AppLocalizations.of(context)!.governorateUnassignedLabel;
  }
  return _isArabic(context) ? governorate.nameAr : governorate.nameEn;
}

String userRoleLabel(BuildContext context, UserRole role) {
  final l10n = AppLocalizations.of(context)!;
  switch (role) {
    case UserRole.customer:
      return l10n.userRoleCustomer;
    case UserRole.driver:
      return l10n.userRoleDriver;
    case UserRole.vendor:
      return l10n.userRoleVendor;
    case UserRole.admin:
      return l10n.userRoleAdmin;
  }
}
