import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/safety_event_model.dart';
import 'package:swiftride/domain/models/safety_event_type.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/services/admin_service.dart';
import 'package:swiftride/services/firestore/firestore_safety_service.dart';
import 'package:swiftride/services/native/native_safety_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Must match NativeChannelConstants.safetyChannel on all three platforms.
  const channel = MethodChannel('com.swiftride.app/safety');

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('NativeSafetyService.sendEmergencySms', () {
    test('refuses an empty number without touching the platform', () async {
      var called = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        called = true;
        return true;
      });

      final service = NativeSafetyService();
      expect(await service.sendEmergencySms(recipientPhone: '  ', messageText: 'x'), isFalse);
      expect(called, isFalse, reason: 'must not open a composer for no recipient');
    });

    test('reports failure when the platform throws', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        throw PlatformException(code: 'sms_unavailable');
      });

      final service = NativeSafetyService();

      // Previously this returned true unconditionally, so the app reported an
      // emergency SMS that had never been composed.
      expect(
        await service.sendEmergencySms(recipientPhone: '+923001234567', messageText: 'help'),
        isFalse,
      );
    });

    test('reports failure when the platform returns null or false', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => null);

      final service = NativeSafetyService();
      expect(
        await service.sendEmergencySms(recipientPhone: '+923001234567', messageText: 'help'),
        isFalse,
      );

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async => false);
      expect(
        await service.sendEmergencySms(recipientPhone: '+923001234567', messageText: 'help'),
        isFalse,
      );
    });

    test('passes the number and body through when the composer opens', () async {
      MethodCall? seen;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        seen = call;
        return true;
      });

      final service = NativeSafetyService();
      final ok = await service.sendEmergencySms(
        recipientPhone: '+923001234567',
        messageText: 'SwiftRide emergency. I need help.',
      );

      expect(ok, isTrue);
      expect(seen!.method, 'sendEmergencySms');
      expect(seen!.arguments['phone'], '+923001234567');
      expect(seen!.arguments['message'], contains('emergency'));
    });
  });

  group('Driver-side SOS visibility', () {
    test('no alert is surfaced before anything happens', () {
      final provider = RideProvider();

      // The driver cockpit branches on this to show its emergency banner.
      expect(provider.activeSos, isNull);

      provider.dispose();
    });

    test('a recorded SOS is readable for its ride, newest first', () async {
      final safety = FirestoreSafetyService();

      await safety.recordSafetyEvent(SafetyEvent(
        id: 'sos_old',
        rideId: 'ride_sos_1',
        type: SafetyEventType.sos,
        latitude: 33.70,
        longitude: 73.05,
        createdAt: DateTime(2026, 1, 1, 10, 0),
      ));
      await safety.recordSafetyEvent(SafetyEvent(
        id: 'sos_new',
        rideId: 'ride_sos_1',
        type: SafetyEventType.sos,
        latitude: 33.71,
        longitude: 73.06,
        createdAt: DateTime(2026, 1, 1, 10, 5),
      ));
      // A different trip must not leak into this one.
      await safety.recordSafetyEvent(SafetyEvent(
        id: 'sos_other',
        rideId: 'ride_sos_2',
        type: SafetyEventType.sos,
        latitude: 33.72,
        longitude: 73.07,
        createdAt: DateTime(2026, 1, 1, 10, 6),
      ));

      final events = await safety.streamEventsForRide('ride_sos_1').first;

      // streamEventsForRide had no callers at all, so a driver received the
      // notification with nothing behind it in the app.
      expect(events.map((e) => e.id), containsAll(['sos_old', 'sos_new']));
      expect(events.map((e) => e.id), isNot(contains('sos_other')));
      expect(
        events.where((e) => e.resolvedAt == null).first.id,
        isNotNull,
        reason: 'an unresolved alert is what the banner keys off',
      );
    });

    test('a resolved alert is distinguishable from an open one', () async {
      final safety = FirestoreSafetyService();

      await safety.recordSafetyEvent(SafetyEvent(
        id: 'sos_resolved',
        rideId: 'ride_sos_3',
        type: SafetyEventType.sos,
        latitude: 33.70,
        longitude: 73.05,
        resolvedAt: DateTime(2026, 1, 1, 11, 0),
        createdAt: DateTime(2026, 1, 1, 10, 0),
      ));

      final events = await safety.streamEventsForRide('ride_sos_3').first;

      expect(events.single.resolvedAt, isNotNull);
    });

    test('an unknown position is zero, not a city centre', () {
      final event = SafetyEvent.fromMap({'rideId': 'r', 'type': 'SOS'});

      // This used to default to Islamabad, so an unlocated alert appeared to
      // come from the capital.
      expect(event.latitude, 0.0);
      expect(event.longitude, 0.0);
    });
  });

  group('Admin safety KPI', () {
    test('reads the platform-wide unresolved count from the server', () {
      final kpis = PlatformKpis.fromServer({
        'totalRides': 120,
        'grossBookingVolume': 45000,
        'zeroCommissionDriverSavings': 5850,
        'activeOnlineDrivers': 14,
        'pendingDriverVerifications': 3,
        'unresolvedSafetyEvents': 2,
      });

      expect(kpis.unresolvedSafetyEvents, 2);
    });

    test('reports zero only when the server actually said zero', () {
      final kpis = PlatformKpis.fromServer({
        'unresolvedSafetyEvents': 0,
      });

      expect(kpis.unresolvedSafetyEvents, 0);
    });

    test('is null, not zero, when the figure is unknown', () {
      final kpis = AdminService().computePlatformKpis(
        rideHistory: const [],
        currentRide: null,
        allDrivers: const [],
        pendingDrivers: const [],
      );

      // Regression guard. The dashboard's SOS tile read a local list that only
      // ever held alerts raised on the viewing device, so it displayed
      // "0 — Unresolved safety flags" while a rider could be in an emergency.
      // An unknown figure must be distinguishable from a genuine all-clear.
      expect(kpis.unresolvedSafetyEvents, isNull);
      expect(kpis.unresolvedSafetyEvents, isNot(0));
    });

    test('a missing field on the server response stays unknown', () {
      final kpis = PlatformKpis.fromServer({'totalRides': 5});

      expect(kpis.unresolvedSafetyEvents, isNull);
    });
  });

  group('SosDispatchResult', () {
    test('a failed dispatch never claims anyone was reached', () {
      const result = SosDispatchResult.failed('No connection');

      // The SOS UI branches on this. Reporting success here is the difference
      // between a rider believing help is coming and knowing it is not.
      expect(result.reachedAnyone, isFalse);
      expect(result.delivered, 0);
      expect(result.notifiedContacts, 0);
      expect(result.unreachablePhones, isEmpty);
      expect(result.message, 'No connection');
    });
  });
}
