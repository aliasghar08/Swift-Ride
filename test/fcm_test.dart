import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/user_model.dart';
import 'package:swiftride/domain/models/user_role.dart';
import 'package:swiftride/services/fcm_service.dart';
import 'package:swiftride/services/firestore/firestore_user_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  AppUser user(String id) => AppUser(
        id: id,
        phone: '+923001234567',
        fullName: 'Test User',
        role: UserRole.rider,
        createdAt: DateTime(2026, 1, 1),
      );

  group('FcmService', () {
    test('starts unregistered', () {
      final service = FcmService();

      // The backend fans out to `fcmTokens` on each user document. Nothing used
      // to write that array, so it was permanently empty and every push —
      // SOS included — reached nobody.
      expect(service.isRegistered, isFalse);
      expect(service.token, isNull);

      service.dispose();
    });

    test('refuses to initialise without a user', () async {
      final service = FcmService();

      expect(await service.initialize(userId: ''), isFalse);
      expect(service.isRegistered, isFalse);

      service.dispose();
    });

    test('unregister is safe when never initialised', () async {
      final service = FcmService();

      // Sign-out runs this unconditionally, so it must not throw.
      await service.unregister();

      expect(service.isRegistered, isFalse);
      service.dispose();
    });
  });

  group('FirestoreUserService token registry', () {
    test('adds a token without duplicating it', () async {
      final users = FirestoreUserService();
      await users.saveUser(user('user_tok'));

      await users.addFcmToken('user_tok', 'token_a');
      await users.addFcmToken('user_tok', 'token_a');
      await users.addFcmToken('user_tok', 'token_b');

      final tokens = await users.fcmTokensFor('user_tok');

      expect(tokens, containsAll(['token_a', 'token_b']));
      expect(tokens.where((t) => t == 'token_a').length, 1);
    });

    test('removes a token on sign-out', () async {
      final users = FirestoreUserService();
      await users.saveUser(user('user_tok2'));

      await users.addFcmToken('user_tok2', 'token_x');
      await users.addFcmToken('user_tok2', 'token_y');
      await users.removeFcmToken('user_tok2', 'token_x');

      final tokens = await users.fcmTokensFor('user_tok2');

      // A stale token means a signed-out device keeps receiving another
      // account's emergency alerts.
      expect(tokens, isNot(contains('token_x')));
      expect(tokens, contains('token_y'));
    });

    test('a token cannot be registered before the user document exists', () async {
      final users = FirestoreUserService();

      // Honest no-op: the Firestore write is an `update`, which fails without an
      // existing document. Pretending the token was stored would leave a device
      // that silently never receives alerts.
      await users.addFcmToken('user_missing', 'token_z');

      expect(await users.fcmTokensFor('user_missing'), isEmpty);
    });
  });
}
