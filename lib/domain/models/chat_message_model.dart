import 'package:cloud_firestore/cloud_firestore.dart';

class ChatMessageModel {
  final String id;
  final String senderId;
  final String senderRole;
  final String text;
  final DateTime createdAt;
  final DateTime? readAt;

  const ChatMessageModel({
    required this.id,
    required this.senderId,
    required this.senderRole,
    required this.text,
    required this.createdAt,
    this.readAt,
  });

  bool get isRead => readAt != null;

  ChatMessageModel copyWith({
    String? id,
    String? senderId,
    String? senderRole,
    String? text,
    DateTime? createdAt,
    DateTime? readAt,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderRole: senderRole ?? this.senderRole,
      text: text ?? this.text,
      createdAt: createdAt ?? this.createdAt,
      readAt: readAt ?? this.readAt,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderRole': senderRole,
      'text': text,
      'createdAt': Timestamp.fromDate(createdAt),
      if (readAt != null) 'readAt': Timestamp.fromDate(readAt!),
    };
  }

  factory ChatMessageModel.fromMap(Map<String, dynamic> map, [String? documentId]) {
    DateTime parseTime(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) {
        final parsed = DateTime.tryParse(val);
        if (parsed != null) return parsed;
      }
      return DateTime.now();
    }

    return ChatMessageModel(
      id: documentId ?? map['id']?.toString() ?? '',
      senderId: map['senderId']?.toString() ?? '',
      senderRole: map['senderRole']?.toString() ?? 'rider',
      text: map['text']?.toString() ?? '',
      createdAt: parseTime(map['createdAt']),
      readAt: map['readAt'] != null ? parseTime(map['readAt']) : null,
    );
  }
}
