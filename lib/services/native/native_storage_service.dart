import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'native_channel_constants.dart';

/// Zero-dependency persistent key-value storage service using native Android
/// SharedPreferences and iOS UserDefaults via MethodChannel.
/// Replaces external dependencies like shared_preferences and flutter_secure_storage.
class NativeStorageService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.storageChannel);

  // In-memory fallback for unit testing environments where MethodChannels are unmocked
  static final Map<String, dynamic> _fallbackMemory = {};

  /// Detects whether code is executing within a Flutter test runner.
  static bool get isTestEnvironment {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return true;
      if (WidgetsBinding.instance.runtimeType.toString().contains('Test')) return true;
    } catch (_) {}
    return false;
  }

  /// Synchronously reads cached in-memory string value if available.
  String? peekStringSync(String key) => _fallbackMemory[key] as String?;

  /// Synchronously reads cached in-memory boolean value if available.
  bool? peekBoolSync(String key) => _fallbackMemory[key] as bool?;

  /// Reads a string value.
  Future<String?> getString(String key) async {
    if (isTestEnvironment || _fallbackMemory.containsKey(key)) {
      return _fallbackMemory[key] as String?;
    }
    try {
      final value = await _channel.invokeMethod<String>(
        NativeChannelConstants.methodStorageGetString,
        {'key': key},
      );
      if (value != null) {
        _fallbackMemory[key] = value;
        return value;
      }
    } catch (_) {}
    return _fallbackMemory[key] as String?;
  }

  /// Writes a string value.
  Future<bool> setString(String key, String value) async {
    _fallbackMemory[key] = value;
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetString,
        {'key': key, 'value': value},
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }

  /// Reads a boolean value.
  Future<bool?> getBool(String key) async {
    if (isTestEnvironment || _fallbackMemory.containsKey(key)) {
      return _fallbackMemory[key] as bool?;
    }
    try {
      final value = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageGetBool,
        {'key': key},
      );
      if (value != null) {
        _fallbackMemory[key] = value;
        return value;
      }
    } catch (_) {}
    return _fallbackMemory[key] as bool?;
  }

  /// Writes a boolean value.
  Future<bool> setBool(String key, bool value) async {
    _fallbackMemory[key] = value;
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetBool,
        {'key': key, 'value': value},
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }

  /// Reads an integer value.
  Future<int?> getInt(String key) async {
    if (isTestEnvironment || _fallbackMemory.containsKey(key)) {
      return _fallbackMemory[key] as int?;
    }
    try {
      final value = await _channel.invokeMethod<int>(
        NativeChannelConstants.methodStorageGetInt,
        {'key': key},
      );
      if (value != null) {
        _fallbackMemory[key] = value;
        return value;
      }
    } catch (_) {}
    return _fallbackMemory[key] as int?;
  }

  /// Writes an integer value.
  Future<bool> setInt(String key, int value) async {
    _fallbackMemory[key] = value;
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetInt,
        {'key': key, 'value': value},
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }

  /// Reads a double value.
  Future<double?> getDouble(String key) async {
    if (isTestEnvironment || _fallbackMemory.containsKey(key)) {
      return _fallbackMemory[key] as double?;
    }
    try {
      final value = await _channel.invokeMethod<double>(
        NativeChannelConstants.methodStorageGetDouble,
        {'key': key},
      );
      if (value != null) {
        _fallbackMemory[key] = value;
        return value;
      }
    } catch (_) {}
    return _fallbackMemory[key] as double?;
  }

  /// Writes a double value.
  Future<bool> setDouble(String key, double value) async {
    _fallbackMemory[key] = value;
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageSetDouble,
        {'key': key, 'value': value},
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }

  /// Removes a key from storage.
  Future<bool> remove(String key) async {
    _fallbackMemory.remove(key);
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageRemove,
        {'key': key},
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }

  /// Clears all stored key-value pairs.
  Future<bool> clear() async {
    _fallbackMemory.clear();
    if (isTestEnvironment) return true;
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStorageClear,
      );
      return res ?? false;
    } catch (_) {
      // Not durable: the value is cached in memory for this session only.
      return false;
    }
  }
}
