import '../core/parsing/safe_enum.dart';

// `admin` is intentionally not offered on the public signup form — accounts
// are promoted to admin out-of-band (e.g. an operator flipping the role
// field directly), not self-service.
enum UserRole { customer, driver, vendor, admin }

class AppUser {
  final String id;
  final String email;
  final String displayName;
  final UserRole role;
  final String? phoneNumber;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.role,
    this.phoneNumber,
  });

  factory AppUser.fromMap(String id, Map<String, dynamic> map) {
    return AppUser(
      id: id,
      email: map['email'] as String,
      displayName: map['displayName'] as String,
      role: enumByName(UserRole.values, map['role'] as String?),
      phoneNumber: map['phoneNumber'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'displayName': displayName,
      'role': role.name,
      'phoneNumber': phoneNumber,
    };
  }
}
