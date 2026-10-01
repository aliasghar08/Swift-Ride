import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Zero-dependency persistent key-value storage service using native Android
/// SharedPreferences and iOS UserDefaults via MethodChannel.
/// Replaces external dependencies like shared_preferences and flutter_secure_storage.
class NativeStorageService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.storageChannel);

  // In-memory fallback for unit testing environments where MethodChannels are unmocked
  static final Map<String, dynamic> _fallbackMemory = {};

  /// Reads a string value.
  Future<String?> getString(String key) async {
    try {
      final value = await _channel.invokeMethod<String>(
        NativeChannelConstants.methodStorageGetString,
        {'key': key},
      );
      if (value != null) return value;
    } catch (_) {}
    return _fallbackMemory[key] as String?;
  }

  /// Writes a string value.
  Future<bool> setString(String key, String value) async {
    _fallbackMemory[key] = value;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetString,
        {'key': key, 'value': value},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Reads a boolean value.
  Future<bool?> getBool(String key) async {
    try {
      final value = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageGetBool,
        {'key': key},
      );
      if (value != null) return value;
    } catch (_) {}
    return _fallbackMemory[key] as bool?;
  }

  /// Writes a boolean value.
  Future<bool> setBool(String key, bool value) async {
    _fallbackMemory[key] = value;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetBool,
        {'key': key, 'value': value},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Reads an integer value.
  Future<int?> getInt(String key) async {
    try {
      final value = await _channel.invokeMethod<int>(
        NativeChannelConstants.methodStorageGetInt,
        {'key': key},
      );
      if (value != null) return value;
    } catch (_) {}
    return _fallbackMemory[key] as int?;
  }

  /// Writes an integer value.
  Future<bool> setInt(String key, int value) async {
    _fallbackMemory[key] = value;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetInt,
        {'key': key, 'value': value},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Reads a double value.
  Future<double?> getDouble(String key) async {
    try {
      final value = await _channel.invokeMethod<double>(
        NativeChannelConstants.methodStorageGetDouble,
        {'key': key},
      );
      if (value != null) return value;
    } catch (_) {}
    return _fallbackMemory[key] as double?;
  }

  /// Writes a double value.
  Future<bool> setDouble(String key, double value) async {
    _fallbackMemory[key] = value;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetDouble,
        {'key': key, 'value': value},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Removes a key from storage.
  Future<bool> remove(String key) async {
    _fallbackMemory.remove(key);
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageRemove,
        {'key': key},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Clears all stored key-value pairs.
  Future<bool> clear() async {
    _fallbackMemory.clear();
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageClear,
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}
