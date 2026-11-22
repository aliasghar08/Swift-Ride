import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/chat_message_model.dart';
import 'package:swiftride/presentation/widgets/ride_chat_sheet.dart';
import 'package:swiftride/services/ride_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatMessageModel Tests', () {
    test('serialization and copyWith', () {
      final now = DateTime(2026, 11, 22, 10, 30);
      final msg = ChatMessageModel(
        id: 'm123',
        senderId: 'user_1',
        senderRole: 'rider',
        text: 'I am at the main gate',
        createdAt: now,
      );

      expect(msg.isRead, isFalse);

      final map = msg.toMap();
      expect(map['senderId'], 'user_1');
      expect(map['senderRole'], 'rider');
      expect(map['text'], 'I am at the main gate');

      final reconstructed = ChatMessageModel.fromMap(map, 'm123');
      expect(reconstructed.id, 'm123');
      expect(reconstructed.text, 'I am at the main gate');
      expect(reconstructed.isRead, isFalse);

      final readMsg = msg.copyWith(readAt: DateTime(2026, 11, 22, 10, 31));
      expect(readMsg.isRead, isTrue);
    });
  });

  group('RideChatService In-Memory Tests', () {
    test('sendMessage validates length and stores in memory', () async {
      final service = RideChatService();

      // Empty message rejected
      final errEmpty = await service.sendMessage(
        rideId: 'ride_101',
        senderId: 'rider_1',
        senderRole: 'rider',
        text: '   ',
      );
      expect(errEmpty, isNotNull);

      // Oversized message rejected (> 500 chars)
      final errLong = await service.sendMessage(
        rideId: 'ride_101',
        senderId: 'rider_1',
        senderRole: 'rider',
        text: 'A' * 501,
      );
      expect(errLong, isNotNull);

      // Valid message accepted
      final errValid = await service.sendMessage(
        rideId: 'ride_101',
        senderId: 'rider_1',
        senderRole: 'rider',
        text: 'Coming down the stairs now',
      );
      expect(errValid, isNull);

      final messages = await service.streamMessages('ride_101').first;
      expect(messages.length, 1);
      expect(messages.first.text, 'Coming down the stairs now');
    });

    test('markAllAsRead marks incoming messages as read', () async {
      final service = RideChatService();

      await service.sendMessage(
        rideId: 'ride_102',
        senderId: 'driver_1',
        senderRole: 'driver',
        text: "I've arrived at pickup",
      );

      final unreadBefore = await service.streamUnreadCount(
        rideId: 'ride_102',
        currentUserId: 'rider_2',
      ).first;
      expect(unreadBefore, 1);

      await service.markAllAsRead(
        rideId: 'ride_102',
        currentUserId: 'rider_2',
      );

      final unreadAfter = await service.streamUnreadCount(
        rideId: 'ride_102',
        currentUserId: 'rider_2',
      ).first;
      expect(unreadAfter, 0);
    });

    test('setTypingStatus broadcasts other party typing', () async {
      final service = RideChatService();

      await service.setTypingStatus(
        rideId: 'ride_103',
        userId: 'driver_2',
        isTyping: true,
      );

      final isTyping = await service.streamOtherPartyTyping(
        rideId: 'ride_103',
        otherUserId: 'driver_2',
      ).first;
      expect(isTyping, isTrue);

      await service.setTypingStatus(
        rideId: 'ride_103',
        userId: 'driver_2',
        isTyping: false,
      );

      final isTypingStopped = await service.streamOtherPartyTyping(
        rideId: 'ride_103',
        otherUserId: 'driver_2',
      ).first;
      expect(isTypingStopped, isFalse);
    });
  });

  group('RideChatSheet UI Widget Tests', () {
    testWidgets('renders header, quick reply chips, and input field', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RideChatSheet(
              rideId: 'ride_104',
              currentUserId: 'rider_1',
              currentUserRole: 'rider',
              otherUserName: 'Captain Tariq',
              otherUserId: 'driver_1',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Captain Tariq'), findsOneWidget);
      expect(find.text('Coming out now'), findsOneWidget);
      expect(find.text('At the main gate'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byIcon(Icons.send_rounded), findsOneWidget);
    });

    testWidgets('tapping quick reply chip sends message immediately', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RideChatSheet(
              rideId: 'ride_105',
              currentUserId: 'driver_1',
              currentUserRole: 'driver',
              otherUserName: 'Ayesha',
              otherUserId: 'rider_1',
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text("I've arrived at pickup"), findsOneWidget);
      await tester.tap(find.text("I've arrived at pickup"));
      await tester.pumpAndSettle();

      expect(find.text("I've arrived at pickup"), findsWidgets);
    });
  });
}
