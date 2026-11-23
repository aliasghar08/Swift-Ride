import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/services/auth_service.dart';
import 'package:swiftride/services/firestore/firestore_user_service.dart';

void main() {
  group('Social Identity Resolution & AppUser Tests', () {
    test('AppUser handles linkedProviders in serialization and copyWith', () {
      final now = DateTime.now();
      final user = AppUser(
        id: 'u_123',
        fullName: 'Ali Asghar',
        phone: '+923001234567',
        email: 'ali@example.com',
        role: UserRole.rider,
        createdAt: now,
        linkedProviders: const ['phone', 'google.com'],
      );

      final map = user.toMap();
      expect(map['linkedProviders'], equals(['phone', 'google.com']));

      final restored = AppUser.fromMap(map);
      expect(restored.id, equals('u_123'));
      expect(restored.phone, equals('+923001234567'));
      expect(restored.email, equals('ali@example.com'));
      expect(restored.linkedProviders, equals(['phone', 'google.com']));

      final updated = restored.copyWith(
        linkedProviders: [...restored.linkedProviders, 'apple.com'],
      );
      expect(updated.linkedProviders, equals(['phone', 'google.com', 'apple.com']));
    });

    test('SocialSessionResult correctly models restoredSession, keepCurrent, and needsPhoneVerification', () {
      const resRestore = SocialSessionResult(
        action: SocialSessionAction.restoredSession,
        targetUid: 'orig_uid_456',
        phoneNumber: '+923001234567',
        hasExistingAccount: true,
      );
      expect(resRestore.action, equals(SocialSessionAction.restoredSession));
      expect(resRestore.targetUid, equals('orig_uid_456'));
      expect(resRestore.phoneNumber, equals('+923001234567'));
      expect(resRestore.hasExistingAccount, isTrue);

      const resKeep = SocialSessionResult(
        action: SocialSessionAction.keepCurrent,
      );
      expect(resKeep.action, equals(SocialSessionAction.keepCurrent));
      expect(resKeep.targetUid, isNull);

      const resVerify = SocialSessionResult(
        action: SocialSessionAction.needsPhoneVerification,
        targetUid: 'orig_uid_456',
        maskedPhone: '+92 ••• •••4567',
        hasExistingAccount: true,
      );
      expect(resVerify.action, equals(SocialSessionAction.needsPhoneVerification));
      expect(resVerify.targetUid, equals('orig_uid_456'));
      expect(resVerify.maskedPhone, equals('+92 ••• •••4567'));
    });

    test('FirestoreUserService.saveUser preserves existing phone number during social sync', () async {
      final service = FirestoreUserService();
      final now = DateTime.now();

      // Step 1: User signs up with phone OTP
      final initialUser = AppUser(
        id: 'user_phone_first',
        fullName: 'Original Rider',
        phone: '+923007654321',
        role: UserRole.rider,
        createdAt: now,
        linkedProviders: const ['phone'],
      );
      await service.saveUser(initialUser);

      final fetched1 = await service.getUser('user_phone_first');
      expect(fetched1, isNotNull);
      expect(fetched1!.phone, equals('+923007654321'));
      expect(fetched1.linkedProviders, equals(['phone']));

      // Step 2: User links Google / logs in via Google with empty phone
      final socialUpdate = AppUser(
        id: 'user_phone_first',
        fullName: 'Original Rider (Google Name)',
        phone: '', // Google does not provide phone
        email: 'rider@gmail.com',
        role: UserRole.rider,
        createdAt: now,
        linkedProviders: const ['google.com'],
      );
      await service.saveUser(socialUpdate);

      // Step 3: Verify phone was preserved and providers merged
      final fetched2 = await service.getUser('user_phone_first');
      expect(fetched2, isNotNull);
      expect(fetched2!.phone, equals('+923007654321'), reason: 'Existing phone must not be overwritten by empty social phone');
      expect(fetched2.email, equals('rider@gmail.com'));
      expect(fetched2.fullName, equals('Original Rider (Google Name)'));
      expect(fetched2.linkedProviders, containsAll(['phone', 'google.com']));

      // Step 4: Explicit non-empty phone update modifies phone
      final newPhoneUpdate = fetched2.copyWith(phone: '+923009999999');
      await service.saveUser(newPhoneUpdate);
      final fetched3 = await service.getUser('user_phone_first');
      expect(fetched3!.phone, equals('+923009999999'));
    });
  });
}
