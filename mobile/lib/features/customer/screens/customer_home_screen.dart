import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/vendor.dart';
import '../../../services/firestore_service.dart';
import '../../auth/providers/auth_provider.dart';

final firestoreServiceProvider =
    Provider<FirestoreService>((ref) => FirestoreService());

final openVendorsProvider = StreamProvider<List<Vendor>>((ref) {
  return ref.watch(firestoreServiceProvider).watchOpenVendors();
});

class CustomerHomeScreen extends ConsumerWidget {
  const CustomerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vendorsAsync = ref.watch(openVendorsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby vendors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authServiceProvider).signOut(),
          ),
        ],
      ),
      body: vendorsAsync.when(
        data: (vendors) {
          if (vendors.isEmpty) {
            return const Center(child: Text('No open vendors right now.'));
          }
          return ListView.builder(
            itemCount: vendors.length,
            itemBuilder: (context, index) {
              final vendor = vendors[index];
              return ListTile(
                title: Text(vendor.name),
                subtitle: Text(vendor.description),
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
