import '../../models/order.dart';

/// Sums [OrderItem.quantity] by item name across [orders] — used to surface
/// a vendor's most-ordered items. Kept as a pure function (no Firebase/
/// Riverpod dependency) so it's trivially unit-testable on its own.
Map<String, int> tallyMenuItemQuantities(List<DeliveryOrder> orders) {
  final tally = <String, int>{};
  for (final order in orders) {
    for (final item in order.items) {
      tally[item.name] = (tally[item.name] ?? 0) + item.quantity;
    }
  }
  return tally;
}
