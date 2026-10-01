import 'package:flutter/foundation.dart';

enum AiInsightType {
  earningsAdvisor('EARNINGS_ADVISOR'),
  safetyCheck('SAFETY_CHECK'),
  maintenanceAlert('MAINTENANCE_ALERT'),
  routeOptimization('ROUTE_OPTIMIZATION');

  final String value;
  const AiInsightType(this.value);

  static AiInsightType fromString(String? val) {
    return AiInsightType.values.firstWhere(
      (e) => e.value == val,
      orElse: () => AiInsightType.earningsAdvisor,
    );
  }
}

@immutable
class AiInsight {
  final String id;
  final String userId;
  final AiInsightType type;
  final String content;
  final Map<String, dynamic> metadata;
  final bool read;
  final DateTime createdAt;

  const AiInsight({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    required this.metadata,
    this.read = false,
    required this.createdAt,
  });

  List<String> get recommendations {
    final list = metadata['recommendations'];
    if (list is List) {
      return list.map((e) => e.toString()).toList();
    }
    return const [];
  }

  double get confidence {
    final conf = metadata['confidence'];
    if (conf is num) return conf.toDouble();
    return 0.90;
  }

  String get urgency {
    return metadata['urgency'] as String? ?? 'LOW';
  }

  int get nextDueInKm {
    final km = metadata['nextDueInKm'];
    if (km is num) return km.toInt();
    return 1500;
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'type': type.value,
      'content': content,
      'metadata': metadata,
      'read': read,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory AiInsight.fromMap(Map<String, dynamic> map, String id) {
    final rawDate = map['createdAt'];
    DateTime date = DateTime.now();
    if (rawDate is String) {
      date = DateTime.tryParse(rawDate) ?? DateTime.now();
    } else if (rawDate is DateTime) {
      date = rawDate;
    }

    return AiInsight(
      id: id,
      userId: map['userId'] as String? ?? '',
      type: AiInsightType.fromString(map['type'] as String?),
      content: map['content'] as String? ?? '',
      metadata: Map<String, dynamic>.from(map['metadata'] as Map? ?? {}),
      read: map['read'] as bool? ?? false,
      createdAt: date,
    );
  }
}
