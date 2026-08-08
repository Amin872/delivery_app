/// Flat courier fee (in SYP) credited to a driver per delivered order.
///
/// There's no per-delivery payout field anywhere in the data model yet — the
/// `DeliveryOrder.total` is the cash-on-delivery amount owed to the vendor,
/// not a driver fee. A flat rate is a deliberate placeholder business rule;
/// swapping in a percentage/variable payout later only means changing how
/// `driver_stats_screen.dart` computes earnings, not this constant's usage
/// elsewhere.
const driverFeePerDelivery = 3000.0;
