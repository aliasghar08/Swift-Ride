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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider; // <-- ADDED IMPORT
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'providers/safety_provider.dart';
import 'services/fcm_service.dart';
import 'ai/ai.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // --- NEW: Ensure an authenticated session exists for Cloud Functions ---
    // This prevents the 'unauthenticated' HttpsError when calling getAutocomplete
    if (FirebaseAuth.instance.currentUser == null) {
      debugPrint('[Auth] No active session found. Signing in anonymously...');
      await FirebaseAuth.instance.signInAnonymously();
    }
    // -----------------------------------------------------------------------

    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

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
      child: const SwiftRideApp(initialRoute: '/login'),
    ),
  );
}

class SwiftRideApp extends StatelessWidget {
  final String? initialRoute;

  const SwiftRideApp({super.key, this.initialRoute});

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
          initialRoute: initialRoute ?? AppRouter.initialRoute,
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }
}