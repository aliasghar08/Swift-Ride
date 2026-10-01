import 'package:flutter/material.dart';
import '../provider/custom_provider.dart';
import '../../providers/auth_provider.dart';
import '../../domain/models/user_role.dart';
import '../../presentation/common/mode_app_bar.dart';
import '../../presentation/rider/rider_home_screen.dart';
import '../../presentation/driver/driver_home_screen.dart';
import '../../presentation/admin/admin_dashboard_screen.dart';
import '../../presentation/common/shared_trip_screen.dart';
import '../../ai/ai.dart';

/// The central shell displaying the active role view (Rider, Driver, or Admin)
/// with the persistent top ModeAppBar.
class MainShellScreen extends StatelessWidget {
  const MainShellScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomConsumer<AuthProvider>(
      builder: (context, auth, _) {
        Widget activeView;
        switch (auth.activeRole) {
          case UserRole.driver:
            activeView = const DriverHomeScreen();
            break;
          case UserRole.admin:
            activeView = const AdminDashboardScreen();
            break;
          case UserRole.rider:
            activeView = const RiderHomeScreen();
            break;
        }

        return Scaffold(
          appBar: const ModeAppBar(title: 'SwiftRide'),
          body: activeView,
        );
      },
    );
  }
}

/// Pure Flutter route generator supporting the main app shell and deep-linked trip tracking.
class AppRouter {
  static const String initialRoute = '/';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');

    if (uri.path == '/track') {
      final token = uri.queryParameters['token'];
      return MaterialPageRoute(
        builder: (_) => SharedTripScreen(token: token),
        settings: settings,
      );
    }

    if (uri.path == '/ai-chat') {
      return MaterialPageRoute(
        builder: (_) => const AiChatScreen(),
        settings: settings,
      );
    }

    if (uri.path == '/earnings-advisor') {
      return MaterialPageRoute(
        builder: (_) => const EarningsAdvisorScreen(),
        settings: settings,
      );
    }

    return MaterialPageRoute(
      builder: (_) => const MainShellScreen(),
      settings: settings,
    );
  }
}
