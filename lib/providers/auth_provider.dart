import 'package:flutter/foundation.dart';
import '../domain/models/user_model.dart';
import '../domain/models/user_role.dart';

/// Zero-dependency Auth & Role Provider managing the active session.
class AuthProvider extends ChangeNotifier {
  AppUser _currentUser;
  UserRole _activeRole;

  AuthProvider({
    AppUser? initialUser,
    UserRole initialRole = UserRole.rider,
  })  : _currentUser = initialUser ??
            AppUser(
              id: 'user_alex_101',
              fullName: 'Alex Morgan',
              phone: '+1 (555) 234-5678',
              email: 'alex.morgan@example.com',
              role: UserRole.rider,
              rating: 4.95,
              totalRides: 42,
              createdAt: DateTime.now().subtract(const Duration(days: 90)),
            ),
        _activeRole = initialRole;

  AppUser get currentUser => _currentUser;
  UserRole get activeRole => _activeRole;

  void switchRole(UserRole role) {
    if (_activeRole == role) return;
    _activeRole = role;
    notifyListeners();
  }

  void updateUser(AppUser user) {
    _currentUser = user;
    notifyListeners();
  }

  void incrementRidesCount() {
    _currentUser = _currentUser.copyWith(totalRides: _currentUser.totalRides + 1);
    notifyListeners();
  }
}
