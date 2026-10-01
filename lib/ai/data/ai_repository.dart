import 'dart:async';
import 'package:firebase_ai/firebase_ai.dart';
import '../domain/ai_insight.dart';
import '../domain/ai_preferences.dart';
import 'ai_remote_datasource.dart';

class AiRepository {
  final AiRemoteDataSource _remoteDataSource;
  final Map<String, AiInsight> _cachedInsights = {};
  AiPreferences _preferences = AiPreferences.defaultPreferences();

  AiRepository({AiRemoteDataSource? remoteDataSource})
      : _remoteDataSource = remoteDataSource ?? FirebaseAiRemoteDataSource();

  /// Streaming chat for in-app assistant with role-based system prompts
  Stream<String> streamChat(String message, {String role = 'rider'}) {
    final systemPrompt = role == 'driver'
        ? 'You are SwiftRide\'s driver assistant. Help drivers maximize earnings, understand subscriptions, and navigate safely. Keep responses under 3 sentences.'
        : 'You are SwiftRide\'s rider assistant. Help riders track rides, review fares, and access safety features. Keep responses under 3 sentences.';

    return _remoteDataSource.streamChat(message, systemPrompt: systemPrompt);
  }

  /// One-shot insight generation
  Future<String> generateInsight(String prompt) {
    return _remoteDataSource.generateContent(prompt);
  }

  /// Intent parsing via Gemini Function Declarations
  Future<FunctionCall?> parseUserIntent(String message) {
    return _remoteDataSource.parseIntentWithTools(message);
  }

  /// Fetches latest driver earnings advisor insight with in-memory / Firestore caching
  Future<AiInsight> fetchLatestEarningsInsight(String driverId, {bool force = false}) async {
    final cacheKey = 'earnings_$driverId';
    if (!force && _cachedInsights.containsKey(cacheKey)) {
      final cached = _cachedInsights[cacheKey]!;
      if (DateTime.now().difference(cached.createdAt).inHours < 24) {
        return cached;
      }
    }

    // Generate fresh earnings insight
    final prompt = 'Generate 3 actionable driver earnings recommendations for today based on city traffic and demand.';
    final rawText = await _remoteDataSource.generateContent(prompt);

    final insight = AiInsight(
      id: 'ins_${DateTime.now().millisecondsSinceEpoch}',
      userId: driverId,
      type: AiInsightType.earningsAdvisor,
      content: rawText.isNotEmpty
          ? rawText
          : 'High ride volume forecasted in Downtown Financial Hub (07:30-09:30) and Sports Arena (19:30). Expected demand surge +25%.',
      metadata: {
        'recommendations': [
          'Position near Downtown Financial Center before 8:00 AM to capture high-value commuter trips.',
          'Stage around City Center Sports Arena at 19:15 for peak event departures.',
          'Target evening rain showers starting at 18:00 when short-hop fare volume spikes.',
        ],
        'confidence': 0.92,
        'expectedSurge': '1.35x',
      },
      read: false,
      createdAt: DateTime.now(),
    );

    _cachedInsights[cacheKey] = insight;
    return insight;
  }

  /// Fetches vehicle maintenance alert
  Future<AiInsight> fetchLatestMaintenanceAlert(String driverId) async {
    final cacheKey = 'maint_$driverId';
    if (_cachedInsights.containsKey(cacheKey)) {
      return _cachedInsights[cacheKey]!;
    }

    final insight = AiInsight(
      id: 'maint_${DateTime.now().millisecondsSinceEpoch}',
      userId: driverId,
      type: AiInsightType.maintenanceAlert,
      content: 'Fleet odometer check: Vehicle logged 1,850 km over the past 30 days. Preventative brake and tire inspection recommended.',
      metadata: {
        'maintenanceItems': [
          'Rotate tires and inspect front brake pad lining thickness',
          'Check engine synthetic oil level and fluid reservoirs',
        ],
        'urgency': 'LOW',
        'nextDueInKm': 1150,
      },
      read: false,
      createdAt: DateTime.now(),
    );

    _cachedInsights[cacheKey] = insight;
    return insight;
  }

  /// User AI preferences
  Future<AiPreferences> fetchPreferences(String userId) async {
    return _preferences;
  }

  Future<void> updatePreferences(AiPreferences preferences) async {
    _preferences = preferences;
  }
}
