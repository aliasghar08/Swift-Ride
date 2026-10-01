enum UserRole {
  rider,
  driver,
  admin;

  static UserRole fromString(String? role) {
    switch (role?.toLowerCase()) {
      case 'driver':
        return UserRole.driver;
      case 'admin':
        return UserRole.admin;
      default:
        return UserRole.rider;
    }
  }

  String toDbString() => name;
}
