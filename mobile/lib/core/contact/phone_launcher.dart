import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/order.dart';
import '../errors/error_messages.dart';
import '../location/navigation_launcher.dart' show UrlLaunchFn;
import '../widgets/app_snackbar.dart';

// Everything contact-related on the client: dialing a number, which order
// statuses show a call button, and the one "fetch the number, then dial"
// flow every call button shares. Phone numbers themselves only ever come
// from the getOrderContact callable (FunctionsService.getOrderContact) —
// never from reading another user's document.

/// Hands [phone] to the device dialer (tel: link, external app). Returns
/// false instead of throwing when nothing could handle it.
Future<bool> launchPhoneCall(String phone, {UrlLaunchFn launch = launchUrl}) async {
  try {
    return await launch(Uri(scheme: 'tel', path: phone), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
}

// When each call button is shown. A UI mirror of the status windows
// enforced by functions/src/contacts.ts (which is what actually decides) —
// same relationship as the driver screen's _nextDriverStatus to the server's
// DRIVER_PROGRESSION.
const _customerDriverStatuses = {OrderStatus.driverAssigned, OrderStatus.pickedUp, OrderStatus.delivering};
const _vendorCustomerStatuses = {
  OrderStatus.pending,
  OrderStatus.accepted,
  OrderStatus.preparing,
  OrderStatus.readyForPickup,
  OrderStatus.driverAssigned,
};
const _vendorDriverStatuses = {OrderStatus.driverAssigned, OrderStatus.pickedUp};

bool customerCanCallDriver(DeliveryOrder order) =>
    order.driverId != null && _customerDriverStatuses.contains(order.status);

bool driverCanCallCustomer(DeliveryOrder order) => _customerDriverStatuses.contains(order.status);

bool vendorCanCallCustomer(DeliveryOrder order) => _vendorCustomerStatuses.contains(order.status);

bool vendorCanCallDriver(DeliveryOrder order) =>
    order.driverId != null && _vendorDriverStatuses.contains(order.status);

/// A call button's behavior, with the look left to [builder]: on tap it asks
/// [fetchPhone] (the contact resolver) for the number, then dials it. While
/// that runs, [builder] gets `busy: true` and a null callback, so a double
/// tap can't start two lookups. A refusal or missing number shows the
/// server's localized reason; a dialer failure shows "couldn't start the
/// call".
class PhoneCallAction extends StatefulWidget {
  const PhoneCallAction({
    required this.fetchPhone,
    required this.builder,
    this.launch = launchUrl,
    super.key,
  });

  final Future<String> Function() fetchPhone;
  final Widget Function(BuildContext context, VoidCallback? onPressed, bool busy) builder;
  final UrlLaunchFn launch;

  @override
  State<PhoneCallAction> createState() => _PhoneCallActionState();
}

class _PhoneCallActionState extends State<PhoneCallAction> {
  bool _busy = false;

  Future<void> _call() async {
    if (_busy) return;
    setState(() => _busy = true);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final phone = await widget.fetchPhone();
      final started = await launchPhoneCall(phone, launch: widget.launch);
      if (!started) {
        messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.callFailedMessage, isError: true));
      }
    } catch (error) {
      if (mounted) {
        messenger.showSnackBar(
          buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _busy ? null : _call, _busy);
}
