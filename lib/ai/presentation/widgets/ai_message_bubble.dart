import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../domain/ai_message.dart';
import '../../presentation/../../presentation/common/glass_container.dart';
import '../../presentation/../../presentation/common/staggered_animation.dart';

class AiMessageBubble extends StatelessWidget {
  final AiMessage message;
  final int index;
  final Function(String intent)? onIntentTapped;

  const AiMessageBubble({
    super.key,
    required this.message,
    this.index = 0,
    this.onIntentTapped,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isUser = message.isUser;

    return StaggeredEntryWidget(
      index: index,
      duration: const Duration(milliseconds: 320),
      slideOffset: 16.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              PulsingGlowWidget(
                glowColor: AppTheme.accentCyan,
                minSpread: 1.0,
                maxSpread: 5.0,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppTheme.primaryNavy, AppTheme.accentCyan],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: AppTheme.subtleElevation,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
            ],
            Flexible(
              child: GlassContainer(
                isDark: isDark,
                borderRadius: 18,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                backgroundColor: isUser
                    ? (isDark
                        ? AppTheme.accentTeal.withValues(alpha: 0.18)
                        : AppTheme.accentTeal.withValues(alpha: 0.12))
                    : (isDark
                        ? AppTheme.glassDarkBackground
                        : Colors.white.withValues(alpha: 0.85)),
                borderColor: isUser
                    ? AppTheme.accentTeal.withValues(alpha: 0.45)
                    : (isDark
                        ? AppTheme.accentCyan.withValues(alpha: 0.3)
                        : AppTheme.primaryNavy.withValues(alpha: 0.15)),
                child: Column(
                  crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isUser) ...[
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'SwiftRide AI',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                              color: isDark ? AppTheme.accentCyan : AppTheme.primaryNavy,
                            ),
                          ),
                          if (message.isStreaming) ...[
                            const SizedBox(width: 6),
                            const SizedBox(
                              width: 8,
                              height: 8,
                              child: CircularProgressIndicator(
                                strokeWidth: 1.8,
                                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.accentCyan),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Text(
                      message.content.isEmpty && message.isStreaming
                          ? 'Thinking...'
                          : message.content,
                      style: TextStyle(
                        fontSize: 14.5,
                        height: 1.4,
                        color: isDark ? Colors.white : AppTheme.primaryNavy,
                        fontStyle: message.content.isEmpty ? FontStyle.italic : FontStyle.normal,
                      ),
                    ),
                    if (message.intent != null) ...[
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () => onIntentTapped?.call(message.intent!),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: AppTheme.accentTeal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.accentTeal.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.bolt, size: 14, color: AppTheme.accentTeal),
                              const SizedBox(width: 4),
                              Text(
                                _intentLabel(message.intent!),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.accentTeal,
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_right, size: 14, color: AppTheme.accentTeal),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      _formatTime(message.timestamp),
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (isUser) ...[
              const SizedBox(width: 10),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDark ? AppTheme.accentTeal.withValues(alpha: 0.3) : AppTheme.accentTeal,
                  boxShadow: AppTheme.subtleElevation,
                ),
                child: const Icon(
                  Icons.person,
                  size: 18,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _intentLabel(String intent) {
    switch (intent) {
      case 'track_ride':
        return 'View Active Ride';
      case 'show_earnings':
        return 'Open Earnings Hub';
      case 'trigger_sos':
        return 'Emergency SOS';
      default:
        return 'Quick Action';
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
