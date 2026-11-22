enum UserRole {
  passenger,
  driver,
  admin;

  /// Backward-compatibility alias for legacy code and tests.
  static const UserRole rider = UserRole.passenger;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'driver':
        return UserRole.driver;
      case 'admin':
        return UserRole.admin;
      case 'passenger':
      case 'rider':
      default:
        return UserRole.passenger;
    }
  }

  String toDbString() => name;
}
