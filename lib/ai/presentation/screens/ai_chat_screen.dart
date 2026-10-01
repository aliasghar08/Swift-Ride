import 'package:flutter/material.dart';
import '../../../core/provider/custom_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../domain/models/user_role.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/ride_provider.dart';
import '../../../providers/safety_provider.dart';
import '../../presentation/../../presentation/common/glass_container.dart';
import '../../presentation/../../presentation/common/staggered_animation.dart';
import '../providers/ai_chat_provider.dart';
import '../widgets/ai_message_bubble.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleIntent(BuildContext context, String intent) {
    switch (intent) {
      case 'track_ride':
        final rideProv = CustomChangeNotifierProvider.read<RideProvider>(context);
        if (rideProv.activeRide != null) {
          Navigator.of(context).pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No active ride currently in progress.'),
              backgroundColor: AppTheme.primaryNavy,
            ),
          );
        }
        break;
      case 'show_earnings':
        Navigator.of(context).pushNamed('/earnings-advisor');
        break;
      case 'trigger_sos':
        final safetyProv = CustomChangeNotifierProvider.read<SafetyProvider>(context);
        safetyProv.triggerSos();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS emergency alert dispatched to safety teams.'),
            backgroundColor: Colors.red,
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    final userRole = auth.activeRole == UserRole.driver ? 'driver' : 'rider';

    return CustomConsumer<AiChatProvider>(
      builder: (context, chatProv, _) {
        final messages = chatProv.messages;
        final suggested = chatProv.getSuggestedPrompts(userRole);

        return Scaffold(
          appBar: AppBar(
            title: Row(
              children: [
                PulsingGlowWidget(
                  glowColor: AppTheme.accentCyan,
                  minSpread: 1.0,
                  maxSpread: 4.0,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accentCyan,
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      size: 16,
                      color: AppTheme.primaryNavy,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'SwiftRide AI Assistant',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Powered by Gemini 3.8 Flash',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.normal,
                        color: isDark ? Colors.white60 : Colors.white70,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Reset Conversation',
                onPressed: () => chatProv.clearConversation(),
              ),
            ],
          ),
          body: Column(
            children: [
              // Quick suggestion pills
              Container(
                height: 48,
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  scrollDirection: Axis.horizontal,
                  itemCount: suggested.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (context, idx) {
                    final prompt = suggested[idx];
                    return ActionChip(
                      label: Text(
                        prompt,
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white70 : AppTheme.primaryNavy,
                        ),
                      ),
                      backgroundColor: isDark
                          ? AppTheme.glassDarkBackground
                          : Colors.white.withValues(alpha: 0.8),
                      side: BorderSide(
                        color: AppTheme.accentCyan.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      onPressed: () {
                        _textController.text = prompt;
                        chatProv.sendMessage(
                          prompt,
                          role: userRole,
                          onIntentDetected: (intent) => _handleIntent(context, intent),
                        );
                        _textController.clear();
                        _scrollToBottom();
                      },
                    );
                  },
                ),
              ),

              // Chat message history
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    return AiMessageBubble(
                      key: ValueKey(msg.id),
                      message: msg,
                      index: index,
                      onIntentTapped: (intent) => _handleIntent(context, intent),
                    );
                  },
                ),
              ),

              // Input bar with frosted glass effect
              _buildInputBar(context, chatProv, userRole, isDark),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInputBar(
    BuildContext context,
    AiChatProvider chatProv,
    String userRole,
    bool isDark,
  ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: GlassContainer(
          isDark: isDark,
          borderRadius: 28,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          borderColor: chatProv.isListening
              ? Colors.red.withValues(alpha: 0.7)
              : AppTheme.accentCyan.withValues(alpha: 0.3),
          child: Row(
            children: [
              // Voice Input button with pulsing glow when listening
              if (chatProv.isListening)
                PulsingGlowWidget(
                  glowColor: Colors.red,
                  minSpread: 2.0,
                  maxSpread: 7.0,
                  child: IconButton(
                    icon: const Icon(Icons.mic, color: Colors.red),
                    onPressed: () => chatProv.toggleVoiceListening(),
                  ),
                )
              else
                IconButton(
                  icon: Icon(
                    Icons.mic_none,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                  tooltip: 'Speech to text',
                  onPressed: () {
                    chatProv.toggleVoiceListening(
                      onTranscribed: (text) {
                        _textController.text = text;
                        chatProv.sendMessage(
                          text,
                          role: userRole,
                          onIntentDetected: (intent) => _handleIntent(context, intent),
                        );
                        _textController.clear();
                        _scrollToBottom();
                      },
                    );
                  },
                ),

              Expanded(
                child: TextField(
                  controller: _textController,
                  focusNode: _focusNode,
                  textInputAction: TextInputAction.send,
                  style: TextStyle(
                    fontSize: 14.5,
                    color: isDark ? Colors.white : AppTheme.primaryNavy,
                  ),
                  decoration: InputDecoration(
                    hintText: chatProv.isListening
                        ? 'Listening to your voice...'
                        : 'Ask SwiftRide AI...',
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white38 : Colors.black38,
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  ),
                  onSubmitted: (text) {
                    if (text.trim().isNotEmpty) {
                      chatProv.sendMessage(
                        text,
                        role: userRole,
                        onIntentDetected: (intent) => _handleIntent(context, intent),
                      );
                      _textController.clear();
                      _scrollToBottom();
                    }
                  },
                ),
              ),

              // Send button
              IconButton(
                icon: chatProv.isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        Icons.send_rounded,
                        color: isDark ? AppTheme.accentCyan : AppTheme.accentTeal,
                      ),
                onPressed: chatProv.isGenerating
                    ? null
                    : () {
                        final text = _textController.text;
                        if (text.trim().isNotEmpty) {
                          chatProv.sendMessage(
                            text,
                            role: userRole,
                            onIntentDetected: (intent) => _handleIntent(context, intent),
                          );
                          _textController.clear();
                          _scrollToBottom();
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
