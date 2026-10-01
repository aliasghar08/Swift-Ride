import 'dart:math';

class IdGenerator {
  static final Random _random = Random.secure();

  /// Generates a unique prefixed ID with timestamp and random hex digits.
  static String generate([String prefix = 'id']) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    final randomHex = List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join();
    return '${prefix}_$timestamp$randomHex';
  }

  /// Generates a unique prefixed ID using named prefix parameter.
  static String generateId({String prefix = 'id_'}) {
    final cleanPrefix = prefix.endsWith('_') ? prefix.substring(0, prefix.length - 1) : prefix;
    return generate(cleanPrefix);
  }

  /// Generates a 4-digit numeric verification PIN.
  static String generatePin() {
    return (1000 + _random.nextInt(9000)).toString();
  }

  /// Generates an unguessable 16-character public share token.
  static String generateShareToken() {
    return List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
  }
}
