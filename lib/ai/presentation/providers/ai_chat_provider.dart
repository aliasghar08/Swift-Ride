import 'dart:async';
import 'package:flutter/material.dart';
import '../../data/ai_repository.dart';
import '../../domain/ai_message.dart';

class AiChatProvider extends ChangeNotifier {
  final AiRepository _repository;
  final List<AiMessage> _messages = [];
  bool _isGenerating = false;
  bool _isListening = false;
  String? _lastError;

  AiChatProvider({AiRepository? repository}) : _repository = repository ?? AiRepository() {
    // Initial welcome message
    _messages.add(
      AiMessage.model(
        'Hello! I am your SwiftRide Assistant. How can I assist you with your rides, earnings, or safety today?',
      ),
    );
  }

  List<AiMessage> get messages => List.unmodifiable(_messages);
  bool get isGenerating => _isGenerating;
  bool get isListening => _isListening;
  String? get lastError => _lastError;

  List<String> getSuggestedPrompts(String role) {
    if (role == 'driver') {
      return [
        'How can I maximize earnings today?',
        'Where are current high-demand zones?',
        'Show my vehicle maintenance status',
        'Explain Year 1 zero-commission policy',
      ];
    }
    return [
      'Where is my driver right now?',
      'How are SwiftRide fares calculated?',
      'What safety features are active?',
      'I need to trigger emergency SOS',
    ];
  }

  Future<void> sendMessage(
    String text, {
    String role = 'rider',
    Function(String intent)? onIntentDetected,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isGenerating) return;

    _lastError = null;
    final userMsg = AiMessage.user(trimmed);
    _messages.add(userMsg);
    notifyListeners();

    // 1. Check for action intent via tool declarations
    try {
      final functionCall = await _repository.parseUserIntent(trimmed);
      if (functionCall != null) {
        final intentName = functionCall.name;
        userMsg.copyWith(intent: intentName);

        if (onIntentDetected != null) {
          onIntentDetected(intentName);
        }

        // Add feedback message for recognized intent
        String actionFeedback;
        switch (intentName) {
          case 'track_ride':
            actionFeedback = 'Opening active ride tracker on your live map...';
            break;
          case 'show_earnings':
            actionFeedback = 'Loading your real-time driver earnings dashboard...';
            break;
          case 'trigger_sos':
            actionFeedback = 'ALERT: Initiating SwiftRide emergency SOS protocol...';
            break;
          default:
            actionFeedback = 'Action recognized: $intentName';
        }

        _messages.add(AiMessage.model(actionFeedback, intent: intentName));
        notifyListeners();
        return;
      }
    } catch (e) {
      debugPrint('[AiChatProvider] Intent parsing notice: $e');
    }

    // 2. Stream AI response with Gemini 3.8 Flash
    _isGenerating = true;
    final modelMsg = AiMessage.model('', isStreaming: true);
    _messages.add(modelMsg);
    notifyListeners();

    final buffer = StringBuffer();
    try {
      await for (final chunk in _repository.streamChat(trimmed, role: role)) {
        buffer.write(chunk);
        final lastIdx = _messages.length - 1;
        _messages[lastIdx] = _messages[lastIdx].copyWith(
          content: buffer.toString(),
          isStreaming: true,
        );
        notifyListeners();
      }
    } catch (e) {
      _lastError = e.toString();
      buffer.write(' I apologize, I encountered a temporary connection issue. Please try again.');
    } finally {
      final lastIdx = _messages.length - 1;
      _messages[lastIdx] = _messages[lastIdx].copyWith(
        content: buffer.toString().trim(),
        isStreaming: false,
      );
      _isGenerating = false;
      notifyListeners();
    }
  }

  void toggleVoiceListening({Function(String text)? onTranscribed}) {
    _isListening = !_isListening;
    notifyListeners();

    if (_isListening) {
      // Simulate speech-to-text recognition
      Future.delayed(const Duration(milliseconds: 1400), () {
        if (_isListening) {
          _isListening = false;
          const simulatedText = 'Where is my active driver right now?';
          notifyListeners();
          if (onTranscribed != null) {
            onTranscribed(simulatedText);
          }
        }
      });
    }
  }

  void clearConversation() {
    _messages.clear();
    _messages.add(
      AiMessage.model('Conversation reset. How can I assist you today?'),
    );
    notifyListeners();
  }
}
