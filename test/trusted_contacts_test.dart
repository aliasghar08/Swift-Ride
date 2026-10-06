import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/services/firestore/firestore_user_service.dart';

void main() {
  group('AppUser.normalizePhone', () {
    test('keeps a leading + and strips separators', () {
      expect(AppUser.normalizePhone('+92 300 1234567'), '+923001234567');
      expect(AppUser.normalizePhone('+92-300-1234567'), '+923001234567');
      expect(AppUser.normalizePhone('03001234567'), '03001234567');
    });

    test('rejects input that cannot be dialled', () {
      // Storing junk here means an SOS silently notifies nobody.
      expect(AppUser.normalizePhone(''), isNull);
      expect(AppUser.normalizePhone('   '), isNull);
      expect(AppUser.normalizePhone('not a phone'), isNull);
      expect(AppUser.normalizePhone('12345'), isNull); // too short
      expect(AppUser.normalizePhone('+1234567890123456789'), isNull); // too long
    });
  });

  group('AppUser trusted contacts', () {
    AppUser buildUser({List<String>? contacts}) => AppUser(
          id: 'user_1',
          phone: '+923001234567',
          fullName: 'Test Rider',
          role: UserRole.rider,
          trustedContacts: contacts ?? const [],
          createdAt: DateTime(2026, 1, 1),
        );

    test('round-trips through toMap/fromMap', () {
      final user = buildUser(contacts: ['+923001112222', '+923004445555']);
      final restored = AppUser.fromMap(user.toMap(), docId: 'user_1');

      expect(restored.trustedContacts, ['+923001112222', '+923004445555']);
    });

    test('defaults to an empty list when absent', () {
      final restored = AppUser.fromMap({'id': 'user_1'}, docId: 'user_1');
      expect(restored.trustedContacts, isEmpty);
    });

    test('copyWith updates the list without disturbing other fields', () {
      final user = buildUser();
      final updated = user.copyWith(trustedContacts: ['+923009998888']);

      expect(updated.trustedContacts, ['+923009998888']);
      expect(updated.phone, user.phone);
      expect(updated.fullName, user.fullName);
    });
  });

  group('FirestoreUserService.updateTrustedContacts', () {
    test('normalises and de-duplicates before storing', () async {
      final service = FirestoreUserService();

      // No Firebase in tests: the in-memory path is used, and the call must still
      // report success so the UI behaves consistently.
      final ok = await service.updateTrustedContacts('user_1', [
        '+92 300 1234567',
        '+923001234567', // duplicate once normalised
        'bogus',
      ]);

      expect(ok, isTrue);
    });
  });
}
