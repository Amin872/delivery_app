enum UserRole { customer, driver, vendor }

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
      role: UserRole.values.byName(map['role'] as String),
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
