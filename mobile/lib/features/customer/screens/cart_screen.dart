import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/address.dart';
import '../../../models/vendor.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../../driver/screens/driver_home_screen.dart' show functionsServiceProvider;
import '../providers/cart_provider.dart';
import '../widgets/cart_quantity_control.dart';
import '../widgets/price_breakdown.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
import 'delivery_addresses_screen.dart' show DeliveryAddressesScreen, defaultAddressProvider;
import 'order_tracking_screen.dart';

// The cart's vendor, watched only to preview its delivery fee — the fee
// actually charged is read server-side by createOrder.
final _cartVendorProvider = StreamProvider.autoDispose.family<Vendor, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendor(vendorId);
});

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;
  String? _errorMessage;
  // Set once from the customer's default SavedAddress the first time it
  // loads — a later stream update (e.g. the customer edits the address in
  // another tab) never silently swaps out what's about to be ordered
  // mid-checkout; they'd need to explicitly tap "Change" again.
  SavedAddress? _selectedAddress;
  bool _addressPrefilled = false;

  Future<void> _changeAddress() async {
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    if (appUser == null) return;
    await Navigator.of(context)
        .push(fadeSlideRoute(DeliveryAddressesScreen(customerId: appUser.id)));
    // DeliveryAddressesScreen manages the saved-address list itself (add/
    // edit/delete/set-default) rather than returning a selection — on
    // return, re-sync from whatever is now the default, same as the
    // one-time prefill below.
    if (mounted) setState(() => _selectedAddress = ref.read(defaultAddressProvider(appUser.id)).valueOrNull);
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(cartProvider);
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    final address = _selectedAddress;
    if (cart.isEmpty || cart.vendorId == null || appUser == null || address == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      // Only the customer's choices go to the server: vendor, items and
      // quantities, and which saved address. Names, prices, fee, totals and
      // status are all decided server-side by the createOrder callable —
      // the cart's own amounts are only an on-screen estimate.
      final placed = await ref.read(functionsServiceProvider).createOrder(
            vendorId: cart.vendorId!,
            items: [
              for (final line in cart.lines.values)
                (menuItemId: line.item.id, quantity: line.quantity),
            ],
            addressId: address.id,
          );
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      final currencyFormat = ref.read(currencyFormatProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        buildAppSnackBar(
          Theme.of(context).colorScheme,
          l10n.orderPlacedTotalMessage(currencyFormat.format(placed.total)),
        ),
      ); // Theme.of here uses the State's own (post-build) context, already under the VendorPalette wrap.
      Navigator.of(context)
          .pushReplacement(fadeSlideRoute(OrderTrackingScreen(orderId: placed.orderId)));
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = localizedErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final customerId = ref.watch(currentAppUserProvider).valueOrNull?.id;
    final cartVendor =
        cart.vendorId == null ? null : ref.watch(_cartVendorProvider(cart.vendorId!)).valueOrNull;
    final deliveryFee = cartVendor == null ? null : (cartVendor.deliveryFee ?? 0);
    // Mirrors createOrder's minimum-order check so the customer sees it
    // before submitting; the server still enforces it. A null or zero
    // minimum means none, and nothing is gated while the vendor loads.
    final minimum = cartVendor?.minimumOrderAmount ?? 0;
    final belowMinimum = minimum > 0 && cart.total < minimum;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final colorScheme = vendorTheme.colorScheme;
    final textTheme = vendorTheme.textTheme;

    if (customerId != null) {
      // One-time prefill from the customer's saved default address — never
      // overwrites a selection already made via "Change" (_addressPrefilled
      // guards that), and only fires once per screen instance.
      ref.listen(defaultAddressProvider(customerId), (previous, next) {
        final defaultAddress = next.valueOrNull;
        if (!_addressPrefilled && defaultAddress != null) {
          setState(() {
            _selectedAddress = defaultAddress;
            _addressPrefilled = true;
          });
        }
      });
    }

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.cartTitle),
          actions: const [LanguageToggleButton()],
        ),
        body: ResponsiveCenter(
          child: cart.isEmpty
              ? Center(
                  child: Text(
                    l10n.emptyCartMessage,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                )
              : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final (index, line) in cart.lines.values.indexed)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            line.item.imageUrl != null
                                ? AppNetworkImage(
                                    imageUrl: line.item.imageUrl!,
                                    width: 52,
                                    height: 52,
                                    borderRadius: BorderRadius.circular(10),
                                  )
                                : ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: Container(
                                      width: 52,
                                      height: 52,
                                      color: colorScheme.surfaceContainerHighest,
                                      child: Icon(
                                        Icons.fastfood_outlined,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.item.name,
                                    style: textTheme.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    currencyFormat.format(line.item.price),
                                    style: textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            // The same stepper as the menu cards; a line
                            // is always in the cart here, so its add
                            // state (quantity 0) is never shown.
                            CartQuantityControl(
                              item: line.item,
                              direction: Axis.horizontal,
                              compact: false,
                              onAdd: () => ref
                                  .read(cartProvider.notifier)
                                  .addItem(cart.vendorId!, cart.vendorName ?? '', line.item),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l10n.removeItemTooltip,
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                ref.read(cartProvider.notifier).removeItem(line.item.id);
                              },
                            ),
                          ],
                        ),
                      ),
                    ).staggeredEntrance(index),
                  const Divider(),
                  // An estimate from the cart and the vendor's current fee.
                  // The server recomputes all three when the order is
                  // placed; the confirmation shows its figures, not these.
                  PriceBreakdown(
                    subtotal: cart.total,
                    // Null until the vendor doc has loaded; a vendor with
                    // no fee set charges none (same rule the server uses).
                    deliveryFee: deliveryFee,
                    total: deliveryFee == null ? null : cart.total + deliveryFee,
                  ),
                  const SizedBox(height: 12),
                  _DeliveryLocationTile(
                    key: const ValueKey('cart_address_field'),
                    address: _selectedAddress,
                    onChange: _changeAddress,
                  ),
                  const SizedBox(height: 24),
                  if (belowMinimum)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Row(
                        key: const ValueKey('cart_minimum_order_hint'),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info_outline, size: 18, color: colorScheme.error),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              l10n.minimumOrderNotMetHint(
                                currencyFormat.format(minimum),
                                currencyFormat.format(minimum - cart.total),
                              ),
                              style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  GradientButton(
                    key: const ValueKey('cart_place_order_button'),
                    onPressed: (_isSubmitting || _selectedAddress == null || belowMinimum)
                        ? null
                        : _placeOrder,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [VendorPalette.primaryCyan, VendorPalette.secondaryCyan],
                    ),
                    child: _isSubmitting
                        ? buttonSpinner(colorScheme.onPrimary)
                        : Text(l10n.placeOrderButton),
                  ),
                ],
              ),
            ),
        ),
      ),
    );
  }
}

/// Read-only summary of the delivery location about to be used for this
/// order, with a "Change" affordance — replaces a bare free-text field
/// (Phase 4: coordinates are the primary source of the delivery location,
/// not typed text — see models/address.dart). Rendered inside the cart's
/// own Form purely for layout consistency; validation of "is a location
/// selected" happens via [_CartScreenState._placeOrder]'s own null check
/// and the place-order button's disabled state, not a FormField validator.
class _DeliveryLocationTile extends StatelessWidget {
  const _DeliveryLocationTile({super.key, required this.address, required this.onChange});

  final SavedAddress? address;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (address == null) {
      return Material(
        color: colorScheme.errorContainer.withValues(alpha: 0.4),
        borderRadius: AppRadius.large,
        child: InkWell(
          borderRadius: AppRadius.large,
          onTap: onChange,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Icon(Icons.add_location_alt_outlined, color: colorScheme.error),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(l10n.noDeliveryLocationMessage, style: textTheme.bodyMedium),
                ),
                Text(l10n.addDeliveryLocationButton, style: textTheme.labelLarge),
              ],
            ),
          ),
        ),
      );
    }

    return Material(
      color: colorScheme.surfaceContainer,
      borderRadius: AppRadius.large,
      child: InkWell(
        borderRadius: AppRadius.large,
        onTap: onChange,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Icon(Icons.location_on, color: colorScheme.primary),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      address!.label.isEmpty ? l10n.deliveryAddressLabel : address!.label,
                      style: textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      address!.addressText,
                      style: textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Read-only: these are saved on the address and copied
                    // onto the order by createOrder; edited from the
                    // address screen, not per order.
                    if (address!.deliveryInstructions?.trim().isNotEmpty ?? false)
                      _AddressNote(
                        icon: Icons.info_outline,
                        label: l10n.orderDeliveryInstructionsLabel,
                        text: address!.deliveryInstructions!.trim(),
                      ),
                    if (address!.driverNote?.trim().isNotEmpty ?? false)
                      _AddressNote(
                        icon: Icons.sticky_note_2_outlined,
                        label: l10n.orderDriverNoteLabel,
                        text: address!.driverNote!.trim(),
                      ),
                  ],
                ),
              ),
              TextButton(onPressed: onChange, child: Text(l10n.changeLocationButton)),
            ],
          ),
        ),
      ),
    );
  }
}

/// One labelled line (delivery instructions / driver note) under the
/// selected address; the label is the icon's tooltip and is read out with
/// the text.
class _AddressNote extends StatelessWidget {
  const _AddressNote({required this.icon, required this.label, required this.text});

  final IconData icon;
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: '$label: $text',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Tooltip(message: label, child: Icon(icon, size: 14, color: colorScheme.onSurfaceVariant)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
