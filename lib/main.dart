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
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'providers/safety_provider.dart';
import 'presentation/auth/phone_auth_screen.dart';
import 'services/fuel_price_service.dart';
import 'services/ad_service.dart';
import 'services/native/native_storage_service.dart';
import 'services/push_notification_service.dart';
import 'ai/ai.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Guard all global Flutter/framework errors so UI exceptions don't crash the engine
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('[FlutterError] ${details.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('[PlatformDispatcherError] $error');
    return true; // Handled, prevent hard crash
  };

  if (!kIsWeb) {
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    } catch (fcmErr) {
      debugPrint('[FCM] Background handler registration notice: $fcmErr');
    }
  }

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(milliseconds: 2500));

    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }

    // App Check is non-blocking so Play Integrity token generation never impedes
    // application startup or causes ANR dialogs on devices with slow Play Services.
    FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleDeviceCheckProvider(),
    ).then((_) {
      debugPrint('[AppCheck] Activated successfully');
    }).catchError((appCheckError) {
      debugPrint('[AppCheck] Non-fatal App Check initialization notice: $appCheckError');
    });
  } catch (e) {
    debugPrint('[FirebaseInit] Running in local/test profile: $e');
  }

  // Defer non-critical background services until 3 seconds after the first frame has rendered,
  // ensuring Chromium WebView (AdMob) and HTTP scraping never contend with cold startup.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[Main] First UI frame rendered successfully. Scheduling background services in 3s...');
    Future.delayed(const Duration(seconds: 3), () {
      debugPrint('[Main] Triggering deferred FuelPriceService & AdService background initialization...');
      FuelPriceService().fetchLivePrices();
      AdService.instance.initialize().catchError((adErr) {
        debugPrint('[AdMob] AdService background init notice: $adErr');
      });
      PushNotificationService.instance.initialize(
        onNotificationTap: AppRouter.handleNotificationTap,
      ).catchError((pushErr) {
        debugPrint('[FCM] PushNotificationService init notice: $pushErr');
      });
    });
  });

  String startRoute = '/login';
  try {
    await AiConsentDialog.isConsentGranted().timeout(const Duration(milliseconds: 300));
    final cachedProfile = await NativeStorageService()
        .getString('cached_user_profile')
        .timeout(const Duration(milliseconds: 300));
    if (cachedProfile != null && cachedProfile.isNotEmpty) {
      final hasVerifiedPhone = cachedProfile.contains('"phone":"+') ||
          cachedProfile.contains('"phone": "+') ||
          RegExp(r'"phone"\s*:\s*"[0-9+]{7,}').hasMatch(cachedProfile);
      if (hasVerifiedPhone) {
        startRoute = '/';
      } else {
        await NativeStorageService().remove('cached_user_profile');
      }
    }
  } catch (storageErr) {
    debugPrint('[Main] Error reading cached session: $storageErr');
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
      child: SwiftRideApp(initialRoute: startRoute),
    ),
  );
}

class SwiftRideApp extends StatefulWidget {
  final String? initialRoute;

  const SwiftRideApp({super.key, this.initialRoute});

  @override
  State<SwiftRideApp> createState() => _SwiftRideAppState();
}

class _SwiftRideAppState extends State<SwiftRideApp> with WidgetsBindingObserver {
  GlobalKey<NavigatorState> get _navigatorKey => AppRouter.navigatorKey;
  int _handledSignOutGen = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  bool _isAllowedExternalDeepLink(String? routeName) {
    if (routeName == null || routeName.isEmpty) return false;
    final uri = Uri.tryParse(routeName);
    if (uri == null) return false;
    // Only allow /track deep links from the OS; ignore Firebase Auth reCAPTCHA
    // callback links (e.g. com.googleusercontent.apps...://firebaseauth/link)
    // so they never push MainShellScreen on top of the OTP verification screen.
    return uri.path == '/track';
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) {
    final uriString = routeInformation.uri.toString();
    if (!_isAllowedExternalDeepLink(uriString)) {
      return SynchronousFuture<bool>(true);
    }
    return super.didPushRouteInformation(routeInformation);
  }

  @override
  Widget build(BuildContext context) {
    return CustomConsumer<AuthProvider>(
      builder: (context, auth, _) {
        final effectiveRoute = widget.initialRoute ?? AppRouter.initialRoute;

        if (auth.signOutGeneration != _handledSignOutGen) {
          _handledSignOutGen = auth.signOutGeneration;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigatorKey.currentState?.pushAndRemoveUntil(
              AppRouter.smoothRoute(
                const PhoneAuthScreen(),
                settings: const RouteSettings(name: '/login'),
              ),
              (route) => false,
            );
          });
        }

        return MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'SwiftRide - 2% Commission Platform',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: auth.activeRole == UserRole.driver ? ThemeMode.dark : ThemeMode.light,
          initialRoute: effectiveRoute,
          onGenerateInitialRoutes: (String initialRouteName) {
            return [
              AppRouter.onGenerateRoute(RouteSettings(name: initialRouteName)),
            ];
          },
          onGenerateRoute: AppRouter.onGenerateRoute,
        );
      },
    );
  }
}