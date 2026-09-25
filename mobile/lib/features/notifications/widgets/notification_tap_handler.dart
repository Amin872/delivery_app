import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/app_user.dart';
import '../../../routing/page_transitions.dart';
import '../../customer/screens/order_tracking_screen.dart';
import '../../vendor/screens/vendor_order_detail_screen.dart';
import '../providers/push_notification_provider.dart';

/// The existing screen a tapped order notification opens for [user], or
/// null when the role's home already is the right place (a driver's
/// active delivery lives on DriverHomeScreen) or the role gets no order
/// notifications (admin). Decided by the signed-in role, never by the
/// notification type alone. Whether the order can actually be shown is left
/// to that screen, which already handles a missing or unreadable order
/// (OrderTrackingScreen: localized error; VendorOrderDetailScreen: "no
/// longer in your list").
Widget? notificationDestination(AppUser user, NotificationOrderTarget target) {
  switch (user.role) {
    case UserRole.customer:
      return OrderTrackingScreen(orderId: target.orderId);
    case UserRole.vendor:
      return VendorOrderDetailScreen(vendorId: user.id, orderId: target.orderId);
    case UserRole.driver:
    case UserRole.admin:
      return null;
  }
}

/// Wraps a signed-in role's home (see app_router's _RoleGate) and opens the
/// order a tapped notification points at — including one that arrived
/// before sign-in/role loading finished, which waits in
/// [pendingNotificationTargetProvider] until this widget exists.
class NotificationTapHandler extends ConsumerStatefulWidget {
  const NotificationTapHandler({required this.user, required this.child, super.key});

  final AppUser user;
  final Widget child;

  @override
  ConsumerState<NotificationTapHandler> createState() => _NotificationTapHandlerState();
}

class _NotificationTapHandlerState extends ConsumerState<NotificationTapHandler> {
  @override
  void initState() {
    super.initState();
    // A notification that launched the app is usually already pending by
    // the time the home screen first builds.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open(ref.read(pendingNotificationTargetProvider));
    });
  }

  void _open(NotificationOrderTarget? target) {
    if (target == null) return;
    ref.read(pendingNotificationTargetProvider.notifier).state = null;
    final navigator = Navigator.of(context);
    // Back to this role's home first, so repeated taps don't stack screens.
    navigator.popUntil((route) => route.isFirst);
    final destination = notificationDestination(widget.user, target);
    if (destination != null) navigator.push(fadeSlideRoute(destination));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(pendingNotificationTargetProvider, (previous, next) => _open(next));
    return widget.child;
  }
}
