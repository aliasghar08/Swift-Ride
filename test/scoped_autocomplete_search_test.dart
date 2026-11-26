import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/services/map_service.dart';
import 'package:swiftride/providers/location_provider.dart';
import 'package:swiftride/services/native_map_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MapService.buildScopedSearchQuery - Proximity & City Lock Scoping', () {
    test('General query without city locks to currentCity with 15km radius', () {
      final scoped = MapService.buildScopedSearchQuery(
        'Civil Hospital',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'Civil Hospital');
      expect(scoped.scopedQuery, 'Civil Hospital, Jhang');
      expect(scoped.radiusMeters, 15000.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.isAreaLocked, isFalse);
      expect(scoped.targetCity, 'Jhang');
    });

    test('Query already mentioning currentCity does not duplicate city name', () {
      final scoped = MapService.buildScopedSearchQuery(
        'DHQ Hospital Jhang',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'DHQ Hospital Jhang');
      expect(scoped.scopedQuery, 'DHQ Hospital Jhang');
      expect(scoped.radiusMeters, 15000.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.targetCity, 'Jhang');
    });

    test('Query mentioning external Pakistani city drops city lock and uses 50km radius', () {
      final scoped = MapService.buildScopedSearchQuery(
        'Allied Hospital Faisalabad',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'Allied Hospital Faisalabad');
      expect(scoped.scopedQuery, 'Allied Hospital Faisalabad');
      expect(scoped.radiusMeters, 50000.0);
      expect(scoped.isCityLocked, isFalse);
      expect(scoped.isAreaLocked, isFalse);
      expect(scoped.targetCity, 'faisalabad');
    });

    test('Query for Lahore airport drops local city lock', () {
      final scoped = MapService.buildScopedSearchQuery(
        'Allama Iqbal Airport Lahore',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'Allama Iqbal Airport Lahore');
      expect(scoped.scopedQuery, 'Allama Iqbal Airport Lahore');
      expect(scoped.radiusMeters, 50000.0);
      expect(scoped.isCityLocked, isFalse);
      expect(scoped.targetCity, 'lahore');
    });

    test('House/plot query without area locks to currentArea and currentCity with 2.5km radius', () {
      final scoped = MapService.buildScopedSearchQuery(
        'Plot 757 A',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'Plot 757 A');
      expect(scoped.scopedQuery, 'Plot 757 A, Satellite Town, Jhang');
      expect(scoped.radiusMeters, 2500.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.isAreaLocked, isTrue);
      expect(scoped.targetCity, 'Jhang');
      expect(scoped.targetArea, 'Satellite Town');
    });

    test('House number with prefix (H# 12) locks to immediate neighborhood', () {
      final scoped = MapService.buildScopedSearchQuery(
        'H# 12',
        currentCity: 'Jhang',
        currentArea: 'Civil Lines',
      );

      expect(scoped.rawQuery, 'H# 12');
      expect(scoped.scopedQuery, 'H# 12, Civil Lines, Jhang');
      expect(scoped.radiusMeters, 2500.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.isAreaLocked, isTrue);
    });

    test('House/plot query with explicit area in query locks only to city with 15km radius', () {
      final scoped = MapService.buildScopedSearchQuery(
        'Plot 757 A Satellite Town',
        currentCity: 'Jhang',
        currentArea: 'Civil Lines',
      );

      expect(scoped.rawQuery, 'Plot 757 A Satellite Town');
      expect(scoped.scopedQuery, 'Plot 757 A Satellite Town, Jhang');
      expect(scoped.radiusMeters, 15000.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.isAreaLocked, isFalse);
    });

    test('House query with sector/block keyword in query does not append currentArea', () {
      final scoped = MapService.buildScopedSearchQuery(
        'House 44 Block B',
        currentCity: 'Jhang',
        currentArea: 'Satellite Town',
      );

      expect(scoped.rawQuery, 'House 44 Block B');
      expect(scoped.scopedQuery, 'House 44 Block B, Jhang');
      expect(scoped.radiusMeters, 15000.0);
      expect(scoped.isCityLocked, isTrue);
      expect(scoped.isAreaLocked, isFalse);
    });
  });

  group('LocationProvider - currentCity and currentArea Getters', () {
    test('Default fallback is Jhang when no address is set', () {
      final provider = LocationProvider();
      expect(provider.currentCity, 'Jhang');
      expect(provider.currentArea, '');
    });

    test('Pulls city and neighborhood from NativeGeocodedAddress when available', () {
      final provider = LocationProvider();
      provider.setDetailedAddressForTesting(
        const NativeGeocodedAddress(
          formattedAddress: 'Satellite Town, Jhang, Punjab, Pakistan',
          city: 'Jhang',
          neighborhood: 'Satellite Town',
          street: 'College Road',
        ),
      );

      expect(provider.currentCity, 'Jhang');
      expect(provider.currentArea, 'Satellite Town');
    });

    test('Falls back to street if neighborhood is empty', () {
      final provider = LocationProvider();
      provider.setDetailedAddressForTesting(
        const NativeGeocodedAddress(
          formattedAddress: 'College Road, Jhang, Punjab, Pakistan',
          city: 'Jhang',
          neighborhood: '',
          street: 'College Road',
        ),
      );

      expect(provider.currentCity, 'Jhang');
      expect(provider.currentArea, 'College Road');
    });
  });
}
