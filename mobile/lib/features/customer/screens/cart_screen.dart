import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
import 'delivery_addresses_screen.dart' show defaultAddressProvider;
import 'order_tracking_screen.dart';

class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _formKey = GlobalKey<FormState>();
  final _addressController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;
  // Set once the customer's saved default address has been used to prefill
  // the field, so a later stream update never overwrites text they've
  // already typed or edited.
  bool _addressPrefilled = false;

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    final cart = ref.read(cartProvider);
    final appUser = ref.read(currentAppUserProvider).valueOrNull;
    if (cart.isEmpty || cart.vendorId == null || appUser == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final order = DeliveryOrder(
        id: '',
        customerId: appUser.id,
        vendorId: cart.vendorId!,
        items: cart.lines.values
            .map((line) => OrderItem(
                  menuItemId: line.item.id,
                  name: line.item.name,
                  quantity: line.quantity,
                  unitPrice: line.item.price,
                ))
            .toList(),
        status: OrderStatus.pending,
        total: cart.total,
        deliveryAddress: _addressController.text.trim(),
        createdAt: DateTime.now(),
      );
      final orderId = await ref.read(firestoreServiceProvider).createOrder(order);
      ref.read(cartProvider.notifier).clear();
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      ScaffoldMessenger.of(context).showSnackBar(
        buildAppSnackBar(Theme.of(context).colorScheme, l10n.orderPlacedMessage),
      ); // Theme.of here uses the State's own (post-build) context, already under the VendorPalette wrap.
      Navigator.of(context)
          .pushReplacement(fadeSlideRoute(OrderTrackingScreen(orderId: orderId)));
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
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final colorScheme = vendorTheme.colorScheme;
    final textTheme = vendorTheme.textTheme;

    if (customerId != null) {
      // One-time prefill from the customer's saved default address (see
      // DeliveryAddressesScreen) — never overwrites text they've already
      // typed, and only fires once per screen instance.
      ref.listen(defaultAddressProvider(customerId), (previous, next) {
        final defaultAddress = next.valueOrNull;
        if (!_addressPrefilled && defaultAddress != null && _addressController.text.isEmpty) {
          _addressController.text = defaultAddress.address;
          _addressPrefilled = true;
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
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 52,
                                height: 52,
                                child: line.item.imageUrl != null
                                    ? Image.network(line.item.imageUrl!, fit: BoxFit.cover)
                                    : Container(
                                        color: colorScheme.surfaceContainerHighest,
                                        child: Icon(
                                          Icons.fastfood_outlined,
                                          color: colorScheme.onSurfaceVariant,
                                        ),
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
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(cartProvider.notifier)
                                    .setQuantity(line.item.id, line.quantity - 1);
                              },
                            ),
                            Text('${line.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () {
                                HapticFeedback.selectionClick();
                                ref
                                    .read(cartProvider.notifier)
                                    .setQuantity(line.item.id, line.quantity + 1);
                              },
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
                  ListTile(
                    title: Text(
                      l10n.totalLabel,
                      style: textTheme.titleMedium,
                    ),
                    trailing: Text(
                      currencyFormat.format(cart.total),
                      style: textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('cart_address_field'),
                    controller: _addressController,
                    decoration: InputDecoration(labelText: l10n.deliveryAddressLabel),
                    validator: (value) => (value == null || value.trim().isEmpty)
                        ? l10n.requiredFieldError
                        : null,
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: TextStyle(color: colorScheme.error),
                    ),
                  GradientButton(
                    key: const ValueKey('cart_place_order_button'),
                    onPressed: _isSubmitting ? null : _placeOrder,
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
