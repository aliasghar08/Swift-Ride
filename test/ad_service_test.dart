import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/presentation/common/ad_banner_widget.dart';
import 'package:swiftride/services/ad_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AdService Unit Tests', () {
    test('AdService singleton returns valid test ad unit IDs', () {
      final service = AdService.instance;
      expect(service.bannerAdUnitId, isNotEmpty);
      expect(service.bannerAdUnitId, contains('ca-app-pub-3940256099942544/'));

      expect(service.interstitialAdUnitId, isNotEmpty);
      expect(service.interstitialAdUnitId, contains('ca-app-pub-3940256099942544/'));
    });

    test('showPostRideInterstitial invokes onDismissed safely when no ad is loaded', () {
      var dismissed = false;
      AdService.instance.showPostRideInterstitial(onDismissed: () {
        dismissed = true;
      });
      expect(dismissed, isTrue);
    });

    testWidgets('AdBannerWidget renders safely in test environment without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AdBannerWidget(),
            ),
          ),
        ),
      );

      // In test harness, banner degrades gracefully to SizedBox.shrink() or uninitialized state
      expect(find.byType(AdBannerWidget), findsOneWidget);
    });
  });
}
