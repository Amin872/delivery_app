import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../../models/app_user.dart';
import '../../models/order.dart';

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
