import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(l10n.orderPlacedMessage)));
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => OrderTrackingScreen(orderId: orderId)),
      );
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
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.cartTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: cart.isEmpty
          ? Center(child: Text(l10n.emptyCartMessage))
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  for (final (index, line) in cart.lines.values.indexed)
                    Card(
                      child: ListTile(
                        title: Text(line.item.name),
                        subtitle: Text(currencyFormat.format(line.item.price)),
                        leading: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .setQuantity(line.item.id, line.quantity - 1),
                            ),
                            Text('${line.quantity}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => ref
                                  .read(cartProvider.notifier)
                                  .setQuantity(line.item.id, line.quantity + 1),
                            ),
                          ],
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          tooltip: l10n.removeItemTooltip,
                          onPressed: () =>
                              ref.read(cartProvider.notifier).removeItem(line.item.id),
                        ),
                      ),
                    ).staggeredEntrance(index),
                  const Divider(),
                  ListTile(
                    title: Text(
                      l10n.totalLabel,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    trailing: Text(
                      currencyFormat.format(cart.total),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
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
                      style: TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  GradientButton(
                    onPressed: _isSubmitting ? null : _placeOrder,
                    child: _isSubmitting
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Theme.of(context).colorScheme.onPrimary,
                            ),
                          )
                        : Text(l10n.placeOrderButton),
                  ),
                ],
              ),
            ),
    );
  }
}
