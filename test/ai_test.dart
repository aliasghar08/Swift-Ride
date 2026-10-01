import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/ai/ai.dart';
import 'package:swiftride/core/provider/custom_provider.dart';
import 'package:swiftride/core/theme/app_theme.dart';
import 'package:swiftride/providers/auth_provider.dart';
import 'package:swiftride/providers/ride_provider.dart';
import 'package:swiftride/providers/safety_provider.dart';

void main() {
  group('AI Domain Models Tests', () {
    test('AiMessage serialization and copyWith', () {
      final userMsg = AiMessage.user('Where is my driver?');
      expect(userMsg.isUser, isTrue);
      expect(userMsg.content, 'Where is my driver?');

      final map = userMsg.toMap();
      expect(map['role'], 'user');
      expect(map['content'], 'Where is my driver?');

      final fromMap = AiMessage.fromMap(map, 'id_123');
      expect(fromMap.id, 'id_123');
      expect(fromMap.isUser, isTrue);

      final modelMsg = AiMessage.model('Driver is 2 mins away', isStreaming: true);
      expect(modelMsg.isUser, isFalse);
      expect(modelMsg.isStreaming, isTrue);

      final updated = modelMsg.copyWith(content: 'Driver has arrived!', isStreaming: false);
      expect(updated.content, 'Driver has arrived!');
      expect(updated.isStreaming, isFalse);
    });

    test('AiInsight parsing, recommendation list and confidence', () {
      final map = {
        'userId': 'driver_99',
        'type': 'EARNINGS_ADVISOR',
        'content': 'Target Downtown for morning commuters.',
        'metadata': {
          'recommendations': [
            'Arrive Downtown by 7:30 AM',
            'Stage at Sports Arena at 19:30',
            'Take express lanes',
          ],
          'confidence': 0.94,
          'urgency': 'LOW',
          'nextDueInKm': 2500,
        },
        'read': false,
        'createdAt': DateTime.now().toIso8601String(),
      };

      final insight = AiInsight.fromMap(map, 'ins_01');
      expect(insight.id, 'ins_01');
      expect(insight.type, AiInsightType.earningsAdvisor);
      expect(insight.recommendations.length, 3);
      expect(insight.recommendations.first, 'Arrive Downtown by 7:30 AM');
      expect(insight.confidence, 0.94);
      expect(insight.urgency, 'LOW');
      expect(insight.nextDueInKm, 2500);
    });

    test('AiPreferences serialization and default values', () {
      final prefs = AiPreferences.defaultPreferences();
      expect(prefs.voiceAssistantEnabled, isTrue);
      expect(prefs.autoSafetyCheckEnabled, isTrue);
      expect(prefs.earningsAdvisorEnabled, isTrue);
      expect(prefs.language, 'en');

      final updated = prefs.copyWith(language: 'ur', voiceAssistantEnabled: false);
      expect(updated.language, 'ur');
      expect(updated.voiceAssistantEnabled, isFalse);
    });
  });

  group('AI Data & Repository Tests', () {
    test('AiRepository parses user intent heuristic triggers', () async {
      final repo = AiRepository();

      final trackIntent = await repo.parseUserIntent('Where is my active driver right now?');
      expect(trackIntent, isNotNull);
      expect(trackIntent!.name, 'track_ride');

      final earnIntent = await repo.parseUserIntent('How much did I earn today?');
      expect(earnIntent, isNotNull);
      expect(earnIntent!.name, 'show_earnings');

      final sosIntent = await repo.parseUserIntent('Emergency! Trigger SOS now');
      expect(sosIntent, isNotNull);
      expect(sosIntent!.name, 'trigger_sos');
    });

    test('AiRepository fetches earnings insight and respects 24h cache', () async {
      final repo = AiRepository();
      final insight1 = await repo.fetchLatestEarningsInsight('driver_123');
      expect(insight1.type, AiInsightType.earningsAdvisor);
      expect(insight1.recommendations.isNotEmpty, isTrue);

      final insight2 = await repo.fetchLatestEarningsInsight('driver_123', force: false);
      expect(insight2.id, insight1.id); // cached instance returned
    });

    test('AiRepository streamChat yields message tokens', () async {
      final repo = AiRepository();
      final stream = repo.streamChat('Explain SwiftRide fare structure');
      final chunks = await stream.toList();

      expect(chunks.isNotEmpty, isTrue);
      final combined = chunks.join('');
      expect(combined, contains('SwiftRide'));
    });
  });

  group('AI Presentation Providers Tests', () {
    test('AiChatProvider manages message streaming and intent callbacks', () async {
      final chatProv = AiChatProvider();
      expect(chatProv.messages.length, 1); // Welcome message

      String? detectedIntent;
      await chatProv.sendMessage(
        'Where is my driver?',
        role: 'rider',
        onIntentDetected: (intent) => detectedIntent = intent,
      );

      expect(detectedIntent, 'track_ride');
      expect(chatProv.messages.length, 3); // Welcome + User + Intent Model feedback

      // Test regular streaming message
      await chatProv.sendMessage('Tell me about your safety', role: 'rider');
      expect(chatProv.messages.last.isUser, isFalse);
      expect(chatProv.messages.last.content, isNotEmpty);
      expect(chatProv.messages.last.isStreaming, isFalse);
    });

    test('SafetyCheckProvider triggers, alerts, and dismisses correctly', () {
      final safetyCheck = SafetyCheckProvider();
      expect(safetyCheck.isSafetyActive, isFalse);

      safetyCheck.triggerSafetyCheck(
        rideId: 'ride_abc_1',
        flagType: 'LONG_STOP',
        message: 'Ride stopped unexpectedly for 3 minutes. Is everything OK?',
      );

      expect(safetyCheck.isSafetyActive, isTrue);
      expect(safetyCheck.flagType, 'LONG_STOP');
      expect(safetyCheck.message, contains('stopped unexpectedly'));

      safetyCheck.dismissCheck();
      expect(safetyCheck.isSafetyActive, isFalse);
    });

    test('EarningsAdvisorProvider loads and refreshes driver insight', () async {
      final advisor = EarningsAdvisorProvider();
      expect(advisor.insight, isNull);

      await advisor.loadEarningsInsight('driver_abc');
      expect(advisor.insight, isNotNull);
      expect(advisor.insight!.type, AiInsightType.earningsAdvisor);
      expect(advisor.isLoading, isFalse);
    });
  });

  group('AI Presentation Widgets & Screen Tests', () {
    testWidgets('AiMessageBubble renders user and model variants', (WidgetTester tester) async {
      final userMessage = AiMessage.user('Can you check my fare?');
      final modelMessage = AiMessage.model(
        'SwiftRide fare is \$2.00 base + \$0.50/km.',
        intent: 'show_earnings',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: Column(
              children: [
                AiMessageBubble(message: userMessage, index: 0),
                AiMessageBubble(message: modelMessage, index: 1),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Can you check my fare?'), findsOneWidget);
      expect(find.text('SwiftRide AI'), findsOneWidget);
      expect(find.text('Open Earnings Hub'), findsOneWidget);
    });

    testWidgets('AiInsightCard renders recommendation steps and confidence', (WidgetTester tester) async {
      final insight = AiInsight(
        id: 'ins_test',
        userId: 'driver_test',
        type: AiInsightType.earningsAdvisor,
        content: 'High demand near Airport today.',
        metadata: {
          'recommendations': [
            'Head to Airport terminal before 9:00 AM',
            'Avoid construction detour on 5th Ave',
          ],
          'confidence': 0.95,
        },
        read: false,
        createdAt: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AiInsightCard(insight: insight),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('DAILY EARNINGS ADVISOR'), findsOneWidget);
      expect(find.text('High demand near Airport today.'), findsOneWidget);
      expect(find.text('Head to Airport terminal before 9:00 AM'), findsOneWidget);
      expect(find.text('95% confidence'), findsOneWidget);
    });

    testWidgets('SafetyCheckOverlay renders I\'m OK and Need Help buttons with callbacks', (WidgetTester tester) async {
      bool okTapped = false;
      bool helpTapped = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SafetyCheckOverlay(
              rideId: 'ride_123',
              flagType: 'LONG_STOP',
              message: 'Vehicle stopped for 4 minutes. Need any assistance?',
              onDismiss: () => okTapped = true,
              onNeedHelp: () => helpTapped = true,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('UNEXPECTED STOP DETECTED'), findsOneWidget);
      expect(find.text('Vehicle stopped for 4 minutes. Need any assistance?'), findsOneWidget);

      await tester.tap(find.text("I'm OK"));
      expect(okTapped, isTrue);

      await tester.tap(find.text('Need Help'));
      expect(helpTapped, isTrue);
    });

    testWidgets('AiChatScreen loads with suggestions and input field', (WidgetTester tester) async {
      final authProv = AuthProvider();
      final rideProv = RideProvider();
      final safetyProv = SafetyProvider();
      final chatProv = AiChatProvider();

      await tester.pumpWidget(
        CustomMultiProvider(
          providers: [
            (child) => CustomChangeNotifierProvider<AuthProvider>(
                  notifier: authProv,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<RideProvider>(
                  notifier: rideProv,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<SafetyProvider>(
                  notifier: safetyProv,
                  child: child,
                ),
            (child) => CustomChangeNotifierProvider<AiChatProvider>(
                  notifier: chatProv,
                  child: child,
                ),
          ],
          child: const MaterialApp(
            home: AiChatScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('SwiftRide AI Assistant'), findsOneWidget);
      expect(find.text('Powered by Gemini 3.8 Flash'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });
  });
}
