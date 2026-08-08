import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/vendor.dart';

typedef CartLine = ({MenuItem item, int quantity});

/// In-memory, session-only cart — a single order-in-progress for one vendor.
/// Deliberately not persisted: the cart is meant to be cleared once an order
/// is placed, and losing it on app restart is an acceptable simplification
/// for this phase.
class CartState {
  const CartState({this.vendorId, this.vendorName, this.lines = const {}});

  final String? vendorId;
  final String? vendorName;
  final Map<String, CartLine> lines;

  bool get isEmpty => lines.isEmpty;

  int get itemCount => lines.values.fold(0, (sum, line) => sum + line.quantity);

  double get total =>
      lines.values.fold(0.0, (sum, line) => sum + line.item.price * line.quantity);

  CartState copyWith({Map<String, CartLine>? lines}) {
    return CartState(vendorId: vendorId, vendorName: vendorName, lines: lines ?? this.lines);
  }
}

final cartProvider = StateNotifierProvider<CartController, CartState>((ref) {
  return CartController();
});

class CartController extends StateNotifier<CartState> {
  CartController() : super(const CartState());

  /// Adds [item] from [vendorId]/[vendorName]. Returns `false` without
  /// changing state if the cart already holds items from a different
  /// vendor — the caller should confirm with the user, then call
  /// [replaceWithItem] to start a fresh cart.
  bool addItem(String vendorId, String vendorName, MenuItem item) {
    if (state.vendorId != null && state.vendorId != vendorId) {
      return false;
    }
    _addOrIncrement(vendorId, vendorName, item);
    return true;
  }

  void replaceWithItem(String vendorId, String vendorName, MenuItem item) {
    state = const CartState();
    _addOrIncrement(vendorId, vendorName, item);
  }

  void _addOrIncrement(String vendorId, String vendorName, MenuItem item) {
    final lines = Map<String, CartLine>.from(state.lines);
    final existing = lines[item.id];
    lines[item.id] = (item: item, quantity: (existing?.quantity ?? 0) + 1);
    state = CartState(vendorId: vendorId, vendorName: vendorName, lines: lines);
  }

  void setQuantity(String menuItemId, int quantity) {
    final lines = Map<String, CartLine>.from(state.lines);
    if (quantity <= 0) {
      lines.remove(menuItemId);
    } else {
      final existing = lines[menuItemId];
      if (existing == null) return;
      lines[menuItemId] = (item: existing.item, quantity: quantity);
    }
    state = lines.isEmpty ? const CartState() : state.copyWith(lines: lines);
  }

  void removeItem(String menuItemId) => setQuantity(menuItemId, 0);

  void clear() => state = const CartState();
}
