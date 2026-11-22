import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import '../domain/models/chat_message_model.dart';
import 'firebase_storage_service.dart';

/// Real-time chat service for active rides between riders and drivers.
class RideChatService {
  static final RideChatService _instance = RideChatService._internal();
  factory RideChatService() => _instance;
  RideChatService._internal();

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  // In-memory fallback for unit test environments
  final Map<String, List<ChatMessageModel>> _memoryMessages = {};
  final Map<String, Map<String, bool>> _memoryTyping = {};
  final Map<String, StreamController<List<ChatMessageModel>>> _memoryStreamControllers = {};
  final Map<String, StreamController<bool>> _memoryTypingControllers = {};

  StreamController<List<ChatMessageModel>> _getOrCreateMsgController(String rideId) {
    return _memoryStreamControllers.putIfAbsent(
      rideId,
      () => StreamController<List<ChatMessageModel>>.broadcast(),
    );
  }

  StreamController<bool> _getOrCreateTypingController(String key) {
    return _memoryTypingControllers.putIfAbsent(
      key,
      () => StreamController<bool>.broadcast(),
    );
  }

  /// Streams chat messages for a ride ordered by creation time ascending.
  Stream<List<ChatMessageModel>> streamMessages(String rideId) {
    final fs = _firestore;
    if (fs == null) {
      final controller = _getOrCreateMsgController(rideId);
      final current = _memoryMessages[rideId] ?? [];
      scheduleMicrotask(() => controller.add(List.unmodifiable(current)));
      return controller.stream;
    }

    return fs
        .collection('rides')
        .doc(rideId)
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => ChatMessageModel.fromMap(doc.data(), doc.id))
            .toList());
  }

  /// Sends a new message in the ride chat, with optional rich media.
  Future<String?> sendMessage({
    required String rideId,
    required String senderId,
    required String senderRole,
    required String text,
    String? mediaUrl,
    String? mediaType,
  }) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty && (mediaUrl == null || mediaUrl.isEmpty)) {
      return 'Message cannot be empty.';
    }
    if (cleanText.length > 500) {
      return 'Message cannot exceed 500 characters.';
    }

    final fs = _firestore;
    if (fs == null) {
      final msg = ChatMessageModel(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}_${_memoryMessages[rideId]?.length ?? 0}',
        senderId: senderId,
        senderRole: senderRole,
        text: cleanText,
        createdAt: DateTime.now(),
        mediaUrl: mediaUrl,
        mediaType: mediaType,
      );
      final list = _memoryMessages.putIfAbsent(rideId, () => []);
      list.add(msg);
      _getOrCreateMsgController(rideId).add(List.unmodifiable(list));
      return null;
    }

    try {
      final data = <String, dynamic>{
        'senderId': senderId,
        'senderRole': senderRole,
        'text': cleanText,
        'createdAt': FieldValue.serverTimestamp(),
      };
      if (mediaUrl != null && mediaUrl.isNotEmpty) {
        data['mediaUrl'] = mediaUrl;
      }
      if (mediaType != null && mediaType.isNotEmpty) {
        data['mediaType'] = mediaType;
      }
      await fs.collection('rides').doc(rideId).collection('messages').add(data);
      return null;
    } catch (e) {
      debugPrint('[RideChatService] sendMessage error: $e');
      return 'Failed to deliver message. Please retry.';
    }
  }

  /// Uploads a photo/video/audio attachment to Firebase Storage and delivers it to the ride chat.
  Future<String?> sendMediaMessage({
    required String rideId,
    required String senderId,
    required String senderRole,
    required Uint8List bytes,
    required String fileName,
    String mimeType = 'image/jpeg',
    String? caption,
  }) async {
    try {
      final storageService = FirebaseStorageService();
      final downloadUrl = await storageService.uploadChatMedia(
        rideId: rideId,
        senderId: senderId,
        bytes: bytes,
        fileName: fileName,
        mimeType: mimeType,
      );

      final mediaType = mimeType.startsWith('video/')
          ? 'video'
          : (mimeType.startsWith('audio/') ? 'audio' : 'image');

      return await sendMessage(
        rideId: rideId,
        senderId: senderId,
        senderRole: senderRole,
        text: caption ?? '',
        mediaUrl: downloadUrl,
        mediaType: mediaType,
      );
    } catch (e) {
      debugPrint('[RideChatService] sendMediaMessage error: $e');
      return 'Failed to upload and send media: $e';
    }
  }

  /// Marks a specific message as read by the recipient.
  Future<void> markAsRead({
    required String rideId,
    required String messageId,
  }) async {
    final fs = _firestore;
    if (fs == null) {
      final list = _memoryMessages[rideId];
      if (list != null) {
        final idx = list.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          list[idx] = list[idx].copyWith(readAt: DateTime.now());
          _getOrCreateMsgController(rideId).add(List.unmodifiable(list));
        }
      }
      return;
    }

    try {
      await fs
          .collection('rides')
          .doc(rideId)
          .collection('messages')
          .doc(messageId)
          .update({'readAt': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('[RideChatService] markAsRead error: $e');
    }
  }

  /// Marks all unread incoming messages as read when opening chat.
  Future<void> markAllAsRead({
    required String rideId,
    required String currentUserId,
  }) async {
    final fs = _firestore;
    if (fs == null) {
      final list = _memoryMessages[rideId];
      if (list != null) {
        bool changed = false;
        for (var i = 0; i < list.length; i++) {
          if (list[i].senderId != currentUserId && list[i].readAt == null) {
            list[i] = list[i].copyWith(readAt: DateTime.now());
            changed = true;
          }
        }
        if (changed) {
          _getOrCreateMsgController(rideId).add(List.unmodifiable(list));
        }
      }
      return;
    }

    try {
      final unreadSnap = await fs
          .collection('rides')
          .doc(rideId)
          .collection('messages')
          .where('senderId', isNotEqualTo: currentUserId)
          .where('readAt', isNull: true)
          .get();

      if (unreadSnap.docs.isNotEmpty) {
        final batch = fs.batch();
        for (final doc in unreadSnap.docs) {
          batch.update(doc.reference, {'readAt': FieldValue.serverTimestamp()});
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('[RideChatService] markAllAsRead error: $e');
    }
  }

  /// Updates typing presence for the user on this ride.
  Future<void> setTypingStatus({
    required String rideId,
    required String userId,
    required bool isTyping,
  }) async {
    final fs = _firestore;
    if (fs == null) {
      final typingMap = _memoryTyping.putIfAbsent(rideId, () => {});
      typingMap[userId] = isTyping;
      _getOrCreateTypingController('${rideId}_$userId').add(isTyping);
      return;
    }

    try {
      await fs.collection('rides').doc(rideId).update({
        'typing.$userId': isTyping,
      });
    } catch (e) {
      debugPrint('[RideChatService] setTypingStatus error: $e');
    }
  }

  /// Streams typing status of the other participant.
  Stream<bool> streamOtherPartyTyping({
    required String rideId,
    required String otherUserId,
  }) {
    final fs = _firestore;
    if (fs == null) {
      final controller = _getOrCreateTypingController('${rideId}_$otherUserId');
      final isTyping = _memoryTyping[rideId]?[otherUserId] ?? false;
      scheduleMicrotask(() => controller.add(isTyping));
      return controller.stream;
    }

    return fs.collection('rides').doc(rideId).snapshots().map((snap) {
      if (!snap.exists) return false;
      final data = snap.data();
      final typingMap = data?['typing'] as Map<String, dynamic>?;
      return typingMap?[otherUserId] == true;
    });
  }

  /// Streams live unread message count for the current user.
  Stream<int> streamUnreadCount({
    required String rideId,
    required String currentUserId,
  }) {
    return streamMessages(rideId).map((messages) {
      return messages
          .where((m) => m.senderId != currentUserId && m.readAt == null)
          .length;
    });
  }
}
