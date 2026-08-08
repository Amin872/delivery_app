/// A customer's rating + optional comment for one delivered order, covering
/// both the vendor and the assigned driver in a single doc. Doc id is always
/// the order id (`reviews/{orderId}`) — firestore.rules relies on that to
/// enforce "one review per order" via create-only semantics, with no query
/// needed to check for an existing review.
class Review {
  final String id;
  final String orderId;
  final String customerId;
  final String vendorId;
  final String driverId;
  final int vendorRating;
  final int driverRating;
  final String? comment;
  final DateTime createdAt;

  const Review({
    required this.id,
    required this.orderId,
    required this.customerId,
    required this.vendorId,
    required this.driverId,
    required this.vendorRating,
    required this.driverRating,
    this.comment,
    required this.createdAt,
  });

  factory Review.fromMap(String id, Map<String, dynamic> map) {
    return Review(
      id: id,
      orderId: map['orderId'] as String,
      customerId: map['customerId'] as String,
      vendorId: map['vendorId'] as String,
      driverId: map['driverId'] as String,
      vendorRating: map['vendorRating'] as int,
      driverRating: map['driverRating'] as int,
      comment: map['comment'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['createdAt'] as int),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'orderId': orderId,
      'customerId': customerId,
      'vendorId': vendorId,
      'driverId': driverId,
      'vendorRating': vendorRating,
      'driverRating': driverRating,
      'comment': comment,
      'createdAt': createdAt.millisecondsSinceEpoch,
    };
  }
}
