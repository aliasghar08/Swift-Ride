import 'package:flutter/services.dart';
import 'native_channel_constants.dart';

/// Zero-dependency audio and speech service interfacing with native Android
/// ToneGenerator/TextToSpeech and iOS AVSpeechSynthesizer/AudioServices.
/// Replaces external dependencies like audioplayers and flutter_tts.
class NativeAudioService {
  static const MethodChannel _channel = MethodChannel(NativeChannelConstants.audioChannel);

  /// Speaks [text] aloud using native device Text-to-Speech engine.
  Future<bool> speak(String text) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodSpeakText,
        {'text': text},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Plays a native audio tone or warning siren.
  /// [toneType] can be 'alert', 'siren', 'beep', or 'success'.
  Future<bool> playAlertTone([String toneType = 'alert']) async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodPlayAlertTone,
        {'type': toneType},
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Immediately stops any ongoing speech synthesis or audio tone.
  Future<bool> stop() async {
    try {
      final res = await _channel.invokeMethod<bool>(
        NativeChannelConstants.methodStopAudio,
      );
      return res ?? true;
    } catch (_) {
      return true;
    }
  }
}
