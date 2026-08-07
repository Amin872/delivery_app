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

  const Driver({
    required this.id,
    required this.userId,
    required this.isAvailable,
    this.lastKnownLocation,
  });

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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'isAvailable': isAvailable,
      'lastKnownLocation': lastKnownLocation?.toMap(),
    };
  }
}
