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

  /// Starts native speech-to-text recognition using iOS SFSpeechRecognizer /
  /// Android SpeechRecognizer and returns the transcribed string if available.
  Future<String?> listenForSpeech() async {
    try {
      final transcript = await _channel.invokeMethod<String>(
        NativeChannelConstants.methodStartSpeechListening,
      );
      final trimmed = transcript?.trim();
      return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
    } catch (_) {
      return null;
    }
  }

  /// Stops active speech-to-text recognition session.
  Future<void> stopListeningForSpeech() async {
    try {
      await _channel.invokeMethod<void>(
        NativeChannelConstants.methodStopSpeechListening,
      );
    } catch (_) {}
  }
}
