class DriverLocation {
  final double latitude;
  final double longitude;
  final DateTime updatedAt;

  const DriverLocation({
    required this.latitude,
    required this.longitude,
    required this.updatedAt,
  });

  factory DriverLocation.fromMap(Map<String, dynamic> map) {
    return DriverLocation(
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] as int,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
    };
  }
}

class Driver {
  final String id;
  final String userId;
  final bool isAvailable;
  final DriverLocation? lastKnownLocation;
  // Written only by the `onReviewCreated` Cloud Function trigger (Admin SDK,
  // bypasses firestore.rules) via FieldValue.increment — see the ratings
  // architecture note in CLAUDE.md. Drivers cannot self-inflate these.
  final num ratingSum;
  final int ratingCount;

  const Driver({
    required this.id,
    required this.userId,
    required this.isAvailable,
    this.lastKnownLocation,
    this.ratingSum = 0,
    this.ratingCount = 0,
  });

  double? get averageRating => ratingCount == 0 ? null : ratingSum / ratingCount;

  factory Driver.fromMap(String id, Map<String, dynamic> map) {
    return Driver(
      id: id,
      userId: map['userId'] as String,
      isAvailable: map['isAvailable'] as bool? ?? false,
      lastKnownLocation: map['lastKnownLocation'] != null
          ? DriverLocation.fromMap(
              map['lastKnownLocation'] as Map<String, dynamic>,
            )
          : null,
      ratingSum: map['ratingSum'] as num? ?? 0,
      ratingCount: map['ratingCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'isAvailable': isAvailable,
      'lastKnownLocation': lastKnownLocation?.toMap(),
      'ratingSum': ratingSum,
      'ratingCount': ratingCount,
    };
  }
}
