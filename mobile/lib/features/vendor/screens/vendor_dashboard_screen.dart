import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/order.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

final vendorOrdersProvider =
    StreamProvider.family<List<DeliveryOrder>, String>((ref, vendorId) {
  return ref.watch(firestoreServiceProvider).watchVendorOrders(vendorId);
});

class VendorDashboardScreen extends ConsumerWidget {
  const VendorDashboardScreen({required this.vendorId, super.key});

  final String vendorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(vendorOrdersProvider(vendorId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Incoming orders'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: ordersAsync.when(
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet.'));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                title: Text('Order ${order.id}'),
                subtitle: Text(order.status.name),
                trailing: Text('\$${order.total.toStringAsFixed(2)}'),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }
}
