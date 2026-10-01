import 'package:flutter/foundation.dart';

@immutable
class AiPreferences {
  final bool voiceAssistantEnabled;
  final bool autoSafetyCheckEnabled;
  final bool earningsAdvisorEnabled;
  final String language;
  final DateTime updatedAt;

  const AiPreferences({
    this.voiceAssistantEnabled = true,
    this.autoSafetyCheckEnabled = true,
    this.earningsAdvisorEnabled = true,
    this.language = 'en',
    required this.updatedAt,
  });

  factory AiPreferences.defaultPreferences() {
    return AiPreferences(
      voiceAssistantEnabled: true,
      autoSafetyCheckEnabled: true,
      earningsAdvisorEnabled: true,
      language: 'en',
      updatedAt: DateTime.now(),
    );
  }

  AiPreferences copyWith({
    bool? voiceAssistantEnabled,
    bool? autoSafetyCheckEnabled,
    bool? earningsAdvisorEnabled,
    String? language,
    DateTime? updatedAt,
  }) {
    return AiPreferences(
      voiceAssistantEnabled: voiceAssistantEnabled ?? this.voiceAssistantEnabled,
      autoSafetyCheckEnabled: autoSafetyCheckEnabled ?? this.autoSafetyCheckEnabled,
      earningsAdvisorEnabled: earningsAdvisorEnabled ?? this.earningsAdvisorEnabled,
      language: language ?? this.language,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'voiceAssistantEnabled': voiceAssistantEnabled,
      'autoSafetyCheckEnabled': autoSafetyCheckEnabled,
      'earningsAdvisorEnabled': earningsAdvisorEnabled,
      'language': language,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory AiPreferences.fromMap(Map<String, dynamic> map) {
    final rawDate = map['updatedAt'];
    DateTime date = DateTime.now();
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is DateTime) {
      date = rawDate;
    }

    return AiPreferences(
      voiceAssistantEnabled: map['voiceAssistantEnabled'] as bool? ?? true,
      autoSafetyCheckEnabled: map['autoSafetyCheckEnabled'] as bool? ?? true,
      earningsAdvisorEnabled: map['earningsAdvisorEnabled'] as bool? ?? true,
      language: map['language'] as String? ?? 'en',
      updatedAt: date,
    );
  }
}
