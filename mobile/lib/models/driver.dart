import 'approval_status.dart';

class DriverLocation {
  // Nullable — this same class is stored both at drivers/{driverId}
  // .lastKnownLocation (id implicit from the parent doc, never written
  // here) and orders/{orderId}/driverLocation/current (id explicitly
  // written by LocationService.publishDriverLocation as of Phase 4, for
  // parity with the driverId field Phase 4's DriverLocation spec asks for).
  // A null value simply means "read the id from context" rather than an
  // error.
  final String? driverId;
  final double latitude;
  final double longitude;
  // Degrees, 0-360, true heading of travel — from geolocator's `Position
  // .heading`. Null when the platform/reading didn't report one (e.g. the
  // driver is stationary), never fabricated.
  final double? heading;
  // Meters/second, from geolocator's `Position.speed`. Null for the same
  // reason as [heading].
  final double? speed;
  final DateTime updatedAt;

  const DriverLocation({
    this.driverId,
    required this.latitude,
    required this.longitude,
    this.heading,
    this.speed,
    required this.updatedAt,
  });

  factory DriverLocation.fromMap(Map<String, dynamic> map) {
    return DriverLocation(
      driverId: map['driverId'] as String?,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      heading: (map['heading'] as num?)?.toDouble(),
      speed: (map['speed'] as num?)?.toDouble(),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        map['updatedAt'] as int,
      ),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'driverId': driverId,
      'latitude': latitude,
      'longitude': longitude,
      'heading': heading,
      'speed': speed,
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
  // Admin review state. Only an admin can change it after creation (see
  // firestore.rules' drivers/{driverId} update branches); a driver always
  // starts [ApprovalStatus.pending].
  final ApprovalStatus approvalStatus;

  const Driver({
    required this.id,
    required this.userId,
    required this.isAvailable,
    this.lastKnownLocation,
    this.ratingSum = 0,
    this.ratingCount = 0,
    this.approvalStatus = ApprovalStatus.pending,
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
      // Every driver doc written before this field existed lacks it —
      // missing/unknown parses as pending (never approved), and must not
      // throw, or watchDriver/watchAllDrivers would break for them.
      approvalStatus: approvalStatusFromWire(map['approvalStatus']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'isAvailable': isAvailable,
      'lastKnownLocation': lastKnownLocation?.toMap(),
      'ratingSum': ratingSum,
      'ratingCount': ratingCount,
      'approvalStatus': approvalStatus.name,
    };
  }
}
