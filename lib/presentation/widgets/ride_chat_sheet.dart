import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/models/chat_message_model.dart';
import '../../services/ride_chat_service.dart';

class RideChatSheet extends StatefulWidget {
  final String rideId;
  final String currentUserId;
  final String currentUserRole; // 'rider' or 'driver'
  final String otherUserName;
  final String otherUserId;

  const RideChatSheet({
    super.key,
    required this.rideId,
    required this.currentUserId,
    required this.currentUserRole,
    required this.otherUserName,
    required this.otherUserId,
  });

  static Future<void> show(
    BuildContext context, {
    required String rideId,
    required String currentUserId,
    required String currentUserRole,
    required String otherUserName,
    required String otherUserId,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => RideChatSheet(
        rideId: rideId,
        currentUserId: currentUserId,
        currentUserRole: currentUserRole,
        otherUserName: otherUserName,
        otherUserId: otherUserId,
      ),
    );
  }

  @override
  State<RideChatSheet> createState() => _RideChatSheetState();
}

class _RideChatSheetState extends State<RideChatSheet> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final RideChatService _chatService = RideChatService();
  Timer? _typingTimer;
  bool _isSending = false;

  List<String> get _quickReplies {
    if (widget.currentUserRole == 'driver') {
      return const [
        "I've arrived at pickup",
        '2 mins away',
        'Where are you standing?',
        'Stuck in traffic',
        'Please keep PIN ready',
      ];
    }
    return const [
      'Coming out now',
      'At the main gate',
      'Please call on arrival',
      'I am here',
      'At the pickup point',
    ];
  }

  @override
  void initState() {
    super.initState();
    _chatService.markAllAsRead(
      rideId: widget.rideId,
      currentUserId: widget.currentUserId,
    );
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _chatService.setTypingStatus(
      rideId: widget.rideId,
      userId: widget.currentUserId,
      isTyping: false,
    );
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged(String val) {
    _chatService.setTypingStatus(
      rideId: widget.rideId,
      userId: widget.currentUserId,
      isTyping: val.trim().isNotEmpty,
    );

    _typingTimer?.cancel();
    if (val.trim().isNotEmpty) {
      _typingTimer = Timer(const Duration(seconds: 3), () {
        _chatService.setTypingStatus(
          rideId: widget.rideId,
          userId: widget.currentUserId,
          isTyping: false,
        );
      });
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final text = presetText ?? _textController.text;
    if (text.trim().isEmpty || _isSending) return;

    if (presetText == null) {
      _textController.clear();
      _onTextChanged('');
    }

    setState(() => _isSending = true);
    await _chatService.sendMessage(
      rideId: widget.rideId,
      senderId: widget.currentUserId,
      senderRole: widget.currentUserRole,
      text: text,
    );
    if (mounted) setState(() => _isSending = false);

    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final min = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$min $period';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.75 + (bottomInset > 0 ? bottomInset : 0),
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101726) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 20, spreadRadius: 4),
        ],
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppTheme.primaryBlue.withValues(alpha: 0.15),
                  child: Icon(
                    widget.currentUserRole == 'driver'
                        ? Icons.person_rounded
                        : Icons.drive_eta_rounded,
                    color: AppTheme.primaryBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.otherUserName.isNotEmpty ? widget.otherUserName : 'Trip Chat',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      StreamBuilder<bool>(
                        stream: _chatService.streamOtherPartyTyping(
                          rideId: widget.rideId,
                          otherUserId: widget.otherUserId,
                        ),
                        builder: (context, snap) {
                          final isTyping = snap.data == true;
                          if (isTyping) {
                            return const Text(
                              'typing...',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppTheme.accentCyan,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }
                          return Text(
                            'Active Ride Messages',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Messages stream
          Expanded(
            child: StreamBuilder<List<ChatMessageModel>>(
              stream: _chatService.streamMessages(widget.rideId),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];

                // Mark any newly arrived message as read
                if (messages.any((m) => m.senderId != widget.currentUserId && m.readAt == null)) {
                  _chatService.markAllAsRead(
                    rideId: widget.rideId,
                    currentUserId: widget.currentUserId,
                  );
                }

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chat_bubble_outline_rounded,
                          size: 48,
                          color: Colors.grey.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No messages yet.\nCoordinate pickup details below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                _scrollToBottom();

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg.senderId == widget.currentUserId;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMe
                              ? AppTheme.primaryBlue
                              : (isDark ? const Color(0xFF1E283E) : const Color(0xFFF0F3F8)),
                          borderRadius: BorderRadius.only(
                            topLeft: const Radius.circular(16),
                            topRight: const Radius.circular(16),
                            bottomLeft: Radius.circular(isMe ? 16 : 4),
                            bottomRight: Radius.circular(isMe ? 4 : 16),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              msg.text,
                              style: TextStyle(
                                fontSize: 14,
                                color: isMe
                                    ? Colors.white
                                    : (isDark ? Colors.white : Colors.black87),
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _formatTime(msg.createdAt),
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe ? Colors.white70 : Colors.grey,
                                  ),
                                ),
                                if (isMe) ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    msg.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                                    size: 14,
                                    color: msg.isRead ? const Color(0xFF00E5FF) : Colors.white70,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),

          // Quick Reply Pills
          Container(
            height: 40,
            margin: const EdgeInsets.only(top: 4, bottom: 6),
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _quickReplies.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final reply = _quickReplies[index];
                return ActionChip(
                  label: Text(
                    reply,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                  ),
                  backgroundColor: isDark
                      ? const Color(0xFF1E283E)
                      : Colors.grey.withValues(alpha: 0.12),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  onPressed: () => _sendMessage(reply),
                );
              },
            ),
          ),

          // Input Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141B2D) : const Color(0xFFF7F8FA),
              border: Border(
                top: BorderSide(
                  color: isDark ? Colors.white10 : Colors.black12,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textController,
                    onChanged: _onTextChanged,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    minLines: 1,
                    maxLength: 500,
                    buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      hintStyle: TextStyle(
                        fontSize: 13.5,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      filled: true,
                      fillColor: isDark ? const Color(0xFF1E283E) : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: _isSending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.send_rounded, size: 20),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.primaryBlue,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _isSending ? null : () => _sendMessage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
