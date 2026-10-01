import 'dart:async';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract class AiRemoteDataSource {
  Stream<String> streamChat(String message, {String? systemPrompt});
  Future<String> generateContent(String prompt, {String? systemPrompt});
  Future<FunctionCall?> parseIntentWithTools(String message);
}

class FirebaseAiRemoteDataSource implements AiRemoteDataSource {
  GenerativeModel? _chatModel;
  GenerativeModel? _toolsModel;
  bool _isInitialized = false;

  static const String defaultGeminiModel = String.fromEnvironment(
    'GEMINI_MODEL',
    defaultValue: 'gemini-1.5-flash',
  );

  static const String defaultSystemPrompt =
      "You are SwiftRide's in-app AI assistant for Pakistan. SwiftRide is a zero-commission ride-hailing platform in Year 1. "
      "Standard platform fares are PKR 150 base + PKR 45/km + PKR 5/min. Subscriptions starting Year 2 are PKR 150/day and PKR 3,500/month. "
      "Keep answers concise (under 3 sentences), courteous, and always format monetary amounts in PKR.";

  void _ensureInitialized({String? systemPrompt}) {
    if (_isInitialized && _chatModel != null) return;

    // Gracefully handle uninitialized Firebase (e.g. tests or offline sandbox)
    try {
      if (Firebase.apps.isEmpty) {
        return;
      }

      final ai = FirebaseAI.googleAI();

      _chatModel = ai.generativeModel(
        model: defaultGeminiModel,
        systemInstruction: Content.system(systemPrompt ?? defaultSystemPrompt),
        generationConfig: GenerationConfig(
          maxOutputTokens: 256,
          temperature: 0.7,
        ),
      );

      _toolsModel = ai.generativeModel(
        model: defaultGeminiModel,
        tools: [
          Tool.functionDeclarations([
            FunctionDeclaration(
              'track_ride',
              'Track the user\'s active ride in real time.',
              parameters: {},
            ),
            FunctionDeclaration(
              'show_earnings',
              'Show the driver\'s earnings summary and daily breakdown.',
              parameters: {},
            ),
            FunctionDeclaration(
              'trigger_sos',
              'Trigger the emergency SOS safety feature immediately.',
              parameters: {},
            ),
          ]),
        ],
      );
      _isInitialized = true;
    } catch (e) {
      debugPrint('[FirebaseAiRemoteDataSource] FirebaseAI initialization notice: $e');
    }
  }

  @override
  Stream<String> streamChat(String message, {String? systemPrompt}) async* {
    _ensureInitialized(systemPrompt: systemPrompt);

    if (_chatModel != null) {
      try {
        final stream = _chatModel!.generateContentStream([Content.text(message)]);
        await for (final chunk in stream) {
          final text = chunk.text;
          if (text != null && text.isNotEmpty) {
            yield text;
          }
        }
        return;
      } catch (e) {
        debugPrint('[FirebaseAiRemoteDataSource] Model stream failed, falling back to simulated stream: $e');
      }
    }

    // High quality offline fallback stream for testing/offline states
    final fallbackResponse = _getSmartFallback(message);
    final words = fallbackResponse.split(' ');
    for (int i = 0; i < words.length; i++) {
      await Future.delayed(const Duration(milliseconds: 30));
      yield i == 0 ? words[i] : ' ${words[i]}';
    }
  }

  @override
  Future<String> generateContent(String prompt, {String? systemPrompt}) async {
    _ensureInitialized(systemPrompt: systemPrompt);

    if (_chatModel != null) {
      try {
        final response = await _chatModel!.generateContent([Content.text(prompt)]);
        return response.text ?? _getSmartFallback(prompt);
      } catch (e) {
        debugPrint('[FirebaseAiRemoteDataSource] generateContent error: $e');
      }
    }

    return _getSmartFallback(prompt);
  }

  @override
  Future<FunctionCall?> parseIntentWithTools(String message) async {
    _ensureInitialized();

    if (_toolsModel != null) {
      try {
        final response = await _toolsModel!.generateContent([Content.text(message)]);
        return response.functionCalls.firstOrNull;
      } catch (e) {
        debugPrint('[FirebaseAiRemoteDataSource] Tool parsing error: $e');
      }
    }

    // Heuristic fallback for function calls
    final lower = message.toLowerCase();
    if (lower.contains('track') || lower.contains('driver') || lower.contains('where is')) {
      return const FunctionCall('track_ride', {});
    }
    if (lower.contains('earn') || lower.contains('payout') || lower.contains('income')) {
      return const FunctionCall('show_earnings', {});
    }
    if (lower.contains('sos') || lower.contains('emergency') || lower.contains('danger')) {
      return const FunctionCall('trigger_sos', {});
    }

    return null;
  }

  String _getSmartFallback(String query) {
    final lower = query.toLowerCase();
    if (lower.contains('track') || lower.contains('where')) {
      return 'Your driver is en route and can be viewed on your active ride map. Arrival estimated in 4 minutes.';
    }
    if (lower.contains('fare') || lower.contains('pricing') || lower.contains('cost')) {
      return 'SwiftRide charges PKR 150 base + PKR 45/km + PKR 5/min. Drivers keep 100% of their earnings with zero commission in Year 1.';
    }
    if (lower.contains('safety') || lower.contains('emergency') || lower.contains('sos')) {
      return 'SwiftRide features 24/7 RideCheck monitoring, Share My Trip, and an instant SOS emergency button.';
    }
    if (lower.contains('earning')) {
      return 'Driver earnings update live after every trip with daily instant cashouts and 0% platform deductions.';
    }
    return 'I am your SwiftRide Assistant. How can I help you today with your rides, earnings, or safety?';
  }
}
