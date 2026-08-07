import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/order.dart';
import '../../auth/providers/auth_provider.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;

final availableOrdersProvider = StreamProvider<List<DeliveryOrder>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAvailableOrdersForDrivers();
});

class DriverHomeScreen extends ConsumerWidget {
  const DriverHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(availableOrdersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Available deliveries'),
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
            return const Center(child: Text('No deliveries ready yet.'));
          }
          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return ListTile(
                title: Text('Order ${order.id}'),
                subtitle: Text(order.deliveryAddress),
                trailing: FilledButton(
                  onPressed: () {},
                  child: const Text('Accept'),
                ),
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
