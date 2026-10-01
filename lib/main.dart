import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/provider/custom_provider.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';
import 'domain/models/user_role.dart';
import 'providers/admin_provider.dart';
import 'providers/auth_provider.dart';
import 'providers/driver_provider.dart';
import 'providers/location_provider.dart';
import 'providers/ride_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'firebase_options.dart';
import 'providers/safety_provider.dart';
import 'ai/ai.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // App Check: Use debug provider in debug/simulator mode, and attestation in release
    if (kDebugMode) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidDebugProvider(),
        providerApple: const AppleDebugProvider(),
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: const AndroidPlayIntegrityProvider(),
        providerApple: const AppleDeviceCheckProvider(),
      );
    }
  } catch (e) {
    debugPrint('[FirebaseInit] Running in local/test profile: $e');
  }

  runApp(
    CustomMultiProvider(
      providers: [
        (child) => CustomChangeNotifierProvider<AuthProvider>(
              notifier: AuthProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<DriverProvider>(
              notifier: DriverProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<LocationProvider>(
              notifier: LocationProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<RideProvider>(
              notifier: RideProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<SafetyProvider>(
              notifier: SafetyProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<AdminProvider>(
              notifier: AdminProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<AiChatProvider>(
              notifier: AiChatProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<EarningsAdvisorProvider>(
              notifier: EarningsAdvisorProvider(),
              child: child,
            ),
        (child) => CustomChangeNotifierProvider<SafetyCheckProvider>(
              notifier: SafetyCheckProvider(),
              child: child,
            ),
      ],
      child: const SwiftRideApp(),
    ),
  );
}

class SwiftRideApp extends StatelessWidget {
  const SwiftRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomConsumer<AuthProvider>(
      builder: (context, auth, _) {
        return MaterialApp(
          title: 'SwiftRide - Zero Commission Platform',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: auth.activeRole == UserRole.driver ? ThemeMode.dark : ThemeMode.light,
          initialRoute: AppRouter.initialRoute,
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }
}
