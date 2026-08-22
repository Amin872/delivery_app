import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/city.dart';
import '../../models/order.dart';
import '../../models/vendor.dart';

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

String cityLabel(BuildContext context, City city) {
  final l10n = AppLocalizations.of(context)!;
  switch (city) {
    case City.damascus:
      return l10n.cityDamascus;
    case City.aleppo:
      return l10n.cityAleppo;
    case City.homs:
      return l10n.cityHoms;
    case City.latakia:
      return l10n.cityLatakia;
    case City.tartus:
      return l10n.cityTartus;
  }
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
