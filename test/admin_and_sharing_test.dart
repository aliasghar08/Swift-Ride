import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/admin_service.dart';
import 'package:swiftride/services/firestore/firestore_safety_service.dart';

void main() {
  group('PlatformKpis', () {
    test('maps the getDashboardStats response onto the KPI model', () {
      final kpis = PlatformKpis.fromServer(<String, dynamic>{
        'totalRides': 128,
        'completedRides': 120,
        'activeOnlineDrivers': 7,
        'pendingDriverVerifications': 3,
        'unresolvedSafetyEvents': 1,
        'grossBookingVolume': 250000.0,
        'zeroCommissionDriverSavings': 32500.0,
        'commissionRate': 0.0,
      });

      // These are real platform aggregates. The dashboard previously derived its
      // KPIs from the current session's own ride history only.
      expect(kpis.totalRides, 128);
      expect(kpis.activeDrivers, 7);
      expect(kpis.pendingVerifications, 3);
      expect(kpis.grossMarketplaceValue, 250000.0);
      expect(kpis.driverCommissionSavings, 32500.0);
    });

    test('defaults missing fields to zero rather than throwing', () {
      final kpis = PlatformKpis.fromServer(<String, dynamic>{});
      expect(kpis.totalRides, 0);
      expect(kpis.activeDrivers, 0);
      expect(kpis.grossMarketplaceValue, 0);
    });
  });

  group('FirestoreSafetyService.createShareLink', () {
    test('never fabricates a token when the backend is unreachable', () async {
      final url = await FirestoreSafetyService().createShareLink('ride_test');

      // Regression guard: the share link used to be built from a token invented
      // on-device, so `getSharedTrip` always answered "invalid or expired"
      // because the server had never seen it.
      expect(url, isNull);
    });
  });
}
