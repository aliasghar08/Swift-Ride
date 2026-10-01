import 'package:flutter/foundation.dart';

/// Represents a chat message in the SwiftRide AI assistant.
@immutable
class AiMessage {
  final String id;
  final String content;
  final bool isUser;
  final DateTime timestamp;
  final bool isStreaming;
  final String? intent;
  final Map<String, dynamic>? metadata;

  const AiMessage({
    required this.id,
    required this.content,
    required this.isUser,
    required this.timestamp,
    this.isStreaming = false,
    this.intent,
    this.metadata,
  });

  factory AiMessage.user(String content) {
    return AiMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      isUser: true,
      timestamp: DateTime.now(),
    );
  }

  factory AiMessage.model(
    String content, {
    bool isStreaming = false,
    String? intent,
    Map<String, dynamic>? metadata,
  }) {
    return AiMessage(
      id: 'msg_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      isUser: false,
      timestamp: DateTime.now(),
      isStreaming: isStreaming,
      intent: intent,
      metadata: metadata,
    );
  }

  AiMessage copyWith({
    String? content,
    bool? isStreaming,
    String? intent,
    Map<String, dynamic>? metadata,
  }) {
    return AiMessage(
      id: id,
      content: content ?? this.content,
      isUser: isUser,
      timestamp: timestamp,
      isStreaming: isStreaming ?? this.isStreaming,
      intent: intent ?? this.intent,
      metadata: metadata ?? this.metadata,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': isUser ? 'user' : 'model',
      'content': content,
      'timestamp': timestamp.toIso8601String(),
      if (intent != null) 'intent': intent,
      if (metadata != null) 'metadata': metadata,
    };
  }

  factory AiMessage.fromMap(Map<String, dynamic> map, [String? id]) {
    final role = map['role'] as String? ?? 'user';
    final content = map['content'] as String? ?? '';
    final tsStr = map['timestamp'] as String?;
    final timestamp = tsStr != null ? DateTime.tryParse(tsStr) ?? DateTime.now() : DateTime.now();

    return AiMessage(
      id: id ?? 'msg_${DateTime.now().microsecondsSinceEpoch}',
      content: content,
      isUser: role == 'user',
      timestamp: timestamp,
      intent: map['intent'] as String?,
      metadata: map['metadata'] as Map<String, dynamic>?,
    );
  }
}
