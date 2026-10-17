import 'package:flutter/material.dart';
import '../provider/custom_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../services/fcm_service.dart';
import '../../providers/ride_provider.dart';
import '../../domain/models/user_role.dart';
import '../../presentation/common/mode_app_bar.dart';
import '../../presentation/rider/rider_home_screen.dart';
import '../../presentation/driver/driver_home_screen.dart';
import '../../presentation/admin/admin_dashboard_screen.dart';
import '../../presentation/common/shared_trip_screen.dart';
import '../../ai/ai.dart';
import '../../presentation/auth/phone_auth_screen.dart';
import '../../presentation/rider/ride_history_screen.dart';

/// The central shell displaying the active role view (Rider, Driver, or Admin)
/// with the persistent top ModeAppBar.
class MainShellScreen extends StatefulWidget {
  const MainShellScreen({super.key});

  @override
  State<MainShellScreen> createState() => _MainShellScreenState();
}

class _MainShellScreenState extends State<MainShellScreen> {
  /// Role we last restored state for, so a role switch re-runs restoration.
  UserRole? _restoredForRole;

  final FcmService _fcm = FcmService();
  String? _pushRegisteredFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);

    // Signed out: drop this device's token so it stops receiving the previous
    // account's emergency alerts.
    if (auth.currentUser.id.isEmpty) {
      if (_pushRegisteredFor != null) {
        _pushRegisteredFor = null;
        _restoredForRole = null;
        _fcm.unregister();
      }
      return;
    }

    final role = auth.activeRole;
    if (_restoredForRole == role) return;
    _restoredForRole = role;

    final rideProv = CustomChangeNotifierProvider.of<RideProvider>(context);
    final driverProv = CustomChangeNotifierProvider.of<DriverProvider>(context);
    final asDriver = role == UserRole.driver;

    // Deferred: these notify listeners immediately, which is illegal during the
    // build phase.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Register this device for push. Without it `fcmTokens` stayed empty and
      // every backend push — SOS included — reached nobody.
      final uid = auth.currentUser.id;
      if (uid.isNotEmpty && _pushRegisteredFor != uid) {
        _pushRegisteredFor = uid;
        _fcm.onMessageOpened = (message) {
          debugPrint('[Shell] notification opened: type=${message.data['type']}');
        };
        _fcm.initialize(userId: uid);
      }

      if (asDriver) {
        rideProv.watchAvailableRides();
        // Load the real driver profile and earnings. The cockpit previously
        // showed a fabricated driver with invented takings.
        driverProv.loadForUser(auth.currentUser.id);
      }
      // Restore an in-flight trip after a relaunch, so backgrounding the app
      // mid-ride does not lose the live trip.
      rideProv.resumeActiveRide(auth.currentUser.id, asDriver: asDriver);
    });
  }

  @override
  void dispose() {
    _fcm.dispose();
    super.dispose();
  }

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

/// Pure Flutter route generator supporting the main app shell, phone auth, and deep-linked trip tracking.
class AppRouter {
  static const String initialRoute = '/';

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');

    if (uri.path == '/login') {
      return MaterialPageRoute(
        builder: (_) => const PhoneAuthScreen(),
        settings: settings,
      );
    }

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

    if (uri.path == '/history') {
      return MaterialPageRoute(
        builder: (_) => const RideHistoryScreen(),
        settings: settings,
      );
    }

    return MaterialPageRoute(
      builder: (_) => const MainShellScreen(),
      settings: settings,
    );
  }
}

