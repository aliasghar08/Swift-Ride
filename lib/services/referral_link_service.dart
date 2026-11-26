import 'dart:async';
import 'package:flutter/services.dart';
import 'native/native_channel_constants.dart';
import 'native/native_storage_service.dart';

/// Zero-dependency service for capturing, parsing, persisting, and auto-applying
/// Captain Referral codes from incoming deep links (`swiftride://join?code=...`),
/// Firebase Hosting web links (`https://swift-ride-5ab75.web.app/join?code=...`),
/// and Google Play Store install referrer parameters (`captain_code=...`).
class ReferralLinkService {
  static const String storageKeyPendingReferral = 'pending_captain_referral_code';
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.referralChannel);
  static const MethodChannel _fallbackChannel = MethodChannel(NativeChannelConstants.referralChannelApp);

  static final ReferralLinkService instance = ReferralLinkService._internal();
  factory ReferralLinkService({NativeStorageService? storage}) {
    if (storage != null) {
      return ReferralLinkService._internal(storage: storage);
    }
    return instance;
  }

  final NativeStorageService _storage;
  final StreamController<String> _referralStreamController = StreamController<String>.broadcast();
  Stream<String> get onReferralReceived => _referralStreamController.stream;

  bool _isInitialized = false;

  ReferralLinkService._internal({NativeStorageService? storage})
      : _storage = storage ?? NativeStorageService() {
    _initChannelListener();
  }

  void _initChannelListener() {
    if (_isInitialized) return;
    _isInitialized = true;
    _channel.setMethodCallHandler(_handleNativeCall);
    _fallbackChannel.setMethodCallHandler(_handleNativeCall);
  }

  Future<dynamic> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onReferralCodeReceived') {
      final raw = call.arguments?.toString();
      final parsed = parseCodeFromString(raw);
      if (parsed != null && parsed.isNotEmpty) {
        await savePendingReferralCode(parsed);
        _referralStreamController.add(parsed);
      }
    }
  }

  /// Parses an invite or promo code from a Uri object.
  static String? parseCodeFromUri(Uri uri) {
    // 1. Direct query parameters ?code=... or ?captain_code=... or ?referrer=...
    final direct = uri.queryParameters['code'] ??
        uri.queryParameters['captain_code'] ??
        uri.queryParameters['referrer'];
    if (direct != null && direct.trim().isNotEmpty) {
      final parsedDirect = parseCodeFromString(direct);
      if (parsedDirect != null) return parsedDirect;
    }

    // 2. Fragment parsing e.g. #/join?code=...
    if (uri.fragment.isNotEmpty && uri.fragment.contains('=')) {
      final fragIndex = uri.fragment.indexOf('?');
      if (fragIndex != -1) {
        final queryStr = uri.fragment.substring(fragIndex + 1);
        final fragUri = Uri.parse('dummy://dummy?$queryStr');
        final fragCode = fragUri.queryParameters['code'] ??
            fragUri.queryParameters['captain_code'] ??
            fragUri.queryParameters['referrer'];
        if (fragCode != null && fragCode.trim().isNotEmpty) {
          final parsedFrag = parseCodeFromString(fragCode);
          if (parsedFrag != null) return parsedFrag;
        }
      }
    }

    return null;
  }

  /// Parses an invite code from any raw URL, custom scheme, or Play Store referrer string.
  static String? parseCodeFromString(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    // A. URL or Query string decoding first
    String decoded = trimmed;
    try {
      decoded = Uri.decodeComponent(trimmed);
    } catch (_) {}

    // B. If already just a clean code (e.g. "JHANG0" or "CAPT482" with no URL symbols)
    if (!decoded.contains('/') &&
        !decoded.contains('?') &&
        !decoded.contains('&') &&
        !decoded.contains('=')) {
      return decoded.toUpperCase();
    }

    // C. Check if full URI
    if (decoded.contains('://') || decoded.startsWith('/') || decoded.contains('?')) {
      try {
        final uri = Uri.parse(decoded);
        final fromUri = parseCodeFromUri(uri);
        if (fromUri != null) return fromUri;
      } catch (_) {}
    }

    // D. Split by & or ; (Play Store referrer format: e.g. captain_code=CAPT482 or utm_source=google&captain_code=CAPT482)
    final pairs = decoded.split(RegExp(r'[&;]'));
    for (final pair in pairs) {
      final idx = pair.indexOf('=');
      if (idx != -1) {
        final key = pair.substring(0, idx).trim().toLowerCase();
        final val = pair.substring(idx + 1).trim();
        if (key == 'code' || key == 'captain_code' || key == 'referrer') {
          // In case value is nested query e.g. referrer=captain_code%3DCAPT482
          if (val.contains('=')) {
            final nested = parseCodeFromString(val);
            if (nested != null) return nested;
          }
          if (val.isNotEmpty) {
            return val.toUpperCase();
          }
        }
      }
    }

    return null;
  }

  /// Checks for any initial referral code passed from native intent or Play Store install referrer.
  Future<String?> checkAndCaptureInitialReferralCode() async {
    // 1. Check native channel first
    try {
      final nativeCode = await _channel.invokeMethod<String>('getInitialReferralCode');
      if (nativeCode != null && nativeCode.trim().isNotEmpty) {
        final parsed = parseCodeFromString(nativeCode);
        if (parsed != null) {
          await savePendingReferralCode(parsed);
          try {
            await _channel.invokeMethod('clearReferralCode');
          } catch (_) {}
          return parsed;
        }
      }
    } catch (_) {}

    // 2. Check fallback native channel
    try {
      final nativeCode = await _fallbackChannel.invokeMethod<String>('getInitialReferralCode');
      if (nativeCode != null && nativeCode.trim().isNotEmpty) {
        final parsed = parseCodeFromString(nativeCode);
        if (parsed != null) {
          await savePendingReferralCode(parsed);
          try {
            await _fallbackChannel.invokeMethod('clearReferralCode');
          } catch (_) {}
          return parsed;
        }
      }
    } catch (_) {}

    // 3. Check persistent storage
    return await getPendingReferralCode();
  }

  /// Persists pending referral code in local storage.
  Future<void> savePendingReferralCode(String code) async {
    final clean = code.trim().toUpperCase();
    if (clean.isNotEmpty) {
      await _storage.setString(storageKeyPendingReferral, clean);
    }
  }

  /// Retrieves any saved pending referral code from local storage.
  Future<String?> getPendingReferralCode() async {
    final code = await _storage.getString(storageKeyPendingReferral);
    if (code != null && code.trim().isNotEmpty) {
      return code.trim().toUpperCase();
    }
    return null;
  }

  /// Clears pending referral code once applied.
  Future<void> clearPendingReferralCode() async {
    await _storage.remove(storageKeyPendingReferral);
    try {
      await _channel.invokeMethod('clearReferralCode');
    } catch (_) {}
    try {
      await _fallbackChannel.invokeMethod('clearReferralCode');
    } catch (_) {}
  }
}
