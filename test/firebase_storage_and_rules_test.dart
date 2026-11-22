import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:swiftride/domain/models/chat_message_model.dart';
import 'package:swiftride/domain/models/driver_document_model.dart';
import 'package:swiftride/domain/models/driver_profile_model.dart';
import 'package:swiftride/domain/models/vehicle_info_model.dart';
import 'package:swiftride/providers/driver_provider.dart';
import 'package:swiftride/services/firebase_storage_service.dart';
import 'package:swiftride/services/ride_chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FirebaseStorageService Tests', () {
    late FirebaseStorageService storage;

    setUp(() {
      storage = FirebaseStorageService();
    });

    test('uploadDriverDocument uploads to drivers/{driverId}/documents/ path', () async {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5]);
      final url = await storage.uploadDriverDocument(
        driverId: 'driver_test_99',
        type: DriverDocumentType.cnicFront,
        bytes: sampleBytes,
        mimeType: 'image/jpeg',
      );

      expect(url, contains('drivers%2Fdriver_test_99%2Fdocuments%2FCNIC_FRONT.jpg'));
      expect(storage.memoryUrls['drivers/driver_test_99/documents/CNIC_FRONT.jpg'], equals(url));
    });

    test('uploadVehiclePhoto uploads front and interior photos to drivers/{driverId}/vehicle/ path', () async {
      final sampleBytes = Uint8List.fromList([10, 20, 30]);

      final frontUrl = await storage.uploadVehiclePhoto(
        driverId: 'driver_test_99',
        photoType: 'front',
        bytes: sampleBytes,
        mimeType: 'image/png',
      );
      expect(frontUrl, contains('drivers%2Fdriver_test_99%2Fvehicle%2Ffront.png'));

      final interiorUrl = await storage.uploadVehiclePhoto(
        driverId: 'driver_test_99',
        photoType: 'interior',
        bytes: sampleBytes,
        mimeType: 'image/jpeg',
      );
      expect(interiorUrl, contains('drivers%2Fdriver_test_99%2Fvehicle%2Finterior.jpg'));
    });

    test('uploadUserProfilePhoto uploads to users/{userId}/avatar path', () async {
      final sampleBytes = Uint8List.fromList([99, 100, 101]);
      final url = await storage.uploadUserProfilePhoto(
        userId: 'user_456',
        bytes: sampleBytes,
        mimeType: 'image/jpeg',
      );

      expect(url, contains('users%2Fuser_456%2Favatar.jpg'));
    });

    test('uploadChatMedia uploads to rides/{rideId}/chat/ path', () async {
      final sampleBytes = Uint8List.fromList([7, 8, 9]);
      final url = await storage.uploadChatMedia(
        rideId: 'ride_abc_123',
        senderId: 'rider_01',
        bytes: sampleBytes,
        fileName: 'pickup_landmark.jpg',
        mimeType: 'image/jpeg',
      );

      expect(url, contains('rides%2Fride_abc_123%2Fchat%2F'));
      expect(url, contains('pickup_landmark.jpg'));
    });

    test('uploadSafetyEvidence uploads emergency clips to safety_events/{eventId}/ path', () async {
      final sampleBytes = Uint8List.fromList([255, 216, 255]);
      final url = await storage.uploadSafetyEvidence(
        eventId: 'sos_alert_777',
        bytes: sampleBytes,
        fileName: 'dashcam_incident.mp4',
        mimeType: 'video/mp4',
      );

      expect(url, contains('safety_events%2Fsos_alert_777%2F'));
      expect(url, contains('dashcam_incident.mp4'));
    });

    test('deleteFile removes simulated storage record', () async {
      final sampleBytes = Uint8List.fromList([1, 1, 1]);
      const path = 'users/temp_user/avatar.jpg';
      await storage.uploadBytes(
        storagePath: path,
        bytes: sampleBytes,
        mimeType: 'image/jpeg',
      );
      expect(storage.memoryUrls.containsKey(path), isTrue);

      await storage.deleteFile(path);
      expect(storage.memoryUrls.containsKey(path), isFalse);
    });
  });

  group('ChatMessageModel Rich Media Tests', () {
    test('serializes and deserializes rich media messages correctly', () {
      final now = DateTime(2026, 11, 22, 12, 0);
      final mediaMsg = ChatMessageModel(
        id: 'msg_media_01',
        senderId: 'driver_01',
        senderRole: 'driver',
        text: 'I am parked near this blue gate',
        mediaUrl: 'https://storage.googleapis.com/swift-ride/rides/r1/chat/blue_gate.jpg',
        mediaType: 'image',
        createdAt: now,
      );

      expect(mediaMsg.hasMedia, isTrue);
      expect(mediaMsg.mediaUrl, contains('blue_gate.jpg'));
      expect(mediaMsg.mediaType, equals('image'));

      final map = mediaMsg.toMap();
      expect(map['mediaUrl'], equals('https://storage.googleapis.com/swift-ride/rides/r1/chat/blue_gate.jpg'));
      expect(map['mediaType'], equals('image'));

      final restored = ChatMessageModel.fromMap(map, 'msg_media_01');
      expect(restored.hasMedia, isTrue);
      expect(restored.mediaUrl, equals(mediaMsg.mediaUrl));
      expect(restored.mediaType, equals(mediaMsg.mediaType));
      expect(restored.text, equals('I am parked near this blue gate'));
    });

    test('allows media message with empty caption text', () {
      final photoOnlyMsg = ChatMessageModel(
        id: 'msg_photo_only',
        senderId: 'rider_01',
        senderRole: 'rider',
        text: '',
        mediaUrl: 'https://storage.googleapis.com/swift-ride/rides/r1/chat/landmark.jpg',
        mediaType: 'image',
        createdAt: DateTime.now(),
      );

      expect(photoOnlyMsg.hasMedia, isTrue);
      expect(photoOnlyMsg.text, isEmpty);
    });
  });

  group('RideChatService Rich Media Tests', () {
    test('sendMediaMessage uploads via storage and stores media message', () async {
      final chatService = RideChatService();
      final sampleImage = Uint8List.fromList([137, 80, 78, 71]); // PNG magic bytes

      final err = await chatService.sendMediaMessage(
        rideId: 'ride_test_media',
        senderId: 'rider_test_1',
        senderRole: 'rider',
        bytes: sampleImage,
        fileName: 'landmark.png',
        mimeType: 'image/png',
        caption: 'Look for this landmark',
      );

      expect(err, isNull);

      final messages = await chatService.streamMessages('ride_test_media').first;
      expect(messages.isNotEmpty, isTrue);
      final lastMsg = messages.last;
      expect(lastMsg.hasMedia, isTrue);
      expect(lastMsg.mediaType, equals('image'));
      expect(lastMsg.text, equals('Look for this landmark'));
      expect(lastMsg.mediaUrl, contains('landmark.png'));
    });
  });

  group('DriverProvider Storage Integration Tests', () {
    test('uploadAndVerifyDocument uploads rawBytes to storage and attaches downloadUrl', () async {
      final driverProv = DriverProvider(
        initialProfile: DriverProfile.empty().copyWith(
          userId: 'drv_test_storage_1',
          licenseNumber: 'LHR-987654',
          vehicle: const VehicleInfo(
            make: 'Toyota',
            model: 'Corolla',
            plate: 'ICT-123',
            color: 'White',
            year: 2022,
          ),
        ),
      );

      final sampleBytes = Uint8List.fromList([255, 216, 255, 224]); // JPEG magic bytes
      final doc = await driverProv.uploadAndVerifyDocument(
        type: DriverDocumentType.cnicFront,
        imageBase64: base64Encode(sampleBytes),
        rawBytes: sampleBytes,
        mimeType: 'image/jpeg',
      );

      expect(doc, isNotNull);
      expect(doc!.downloadUrl, isNotNull);
      expect(doc.downloadUrl, contains('drivers%2Fdrv_test_storage_1%2Fdocuments%2FCNIC_FRONT.jpg'));
    });

    test('uploading vehicleFront photo updates driver vehicle frontPhotoUrl', () async {
      final driverProv = DriverProvider(
        initialProfile: DriverProfile.empty().copyWith(
          userId: 'drv_test_storage_2',
          licenseNumber: 'ISB-55555',
          vehicle: const VehicleInfo(
            make: 'Honda',
            model: 'Civic',
            plate: 'ISB-789',
            color: 'Black',
            year: 2023,
          ),
        ),
      );

      final sampleBytes = Uint8List.fromList([1, 2, 3]);
      final doc = await driverProv.uploadAndVerifyDocument(
        type: DriverDocumentType.vehicleFront,
        imageBase64: base64Encode(sampleBytes),
        rawBytes: sampleBytes,
        mimeType: 'image/jpeg',
      );

      expect(doc, isNotNull);
      expect(doc!.downloadUrl, isNotNull);
      expect(driverProv.driverProfile.vehicle.frontPhotoUrl, equals(doc.downloadUrl));
      expect(driverProv.driverProfile.vehicle.hasVisualInspection, isTrue);
    });
  });

  group('Firebase Security Rules File Integrity & Coverage Audit', () {
    test('storage.rules contains all required collections, limits, and type constraints', () {
      final file = File('storage.rules');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains("rules_version = '2'"));
      expect(content, contains('service firebase.storage'));

      // Check all media paths
      expect(content, contains('match /users/{userId}/{fileName}'));
      expect(content, contains('match /drivers/{driverId}/documents/{documentName}'));
      expect(content, contains('match /drivers/{driverId}/vehicle/{photoName}'));
      expect(content, contains('match /rides/{rideId}/chat/{fileName}'));
      expect(content, contains('match /safety_events/{eventId}/{fileName}'));
      expect(content, contains('match /public/{allPaths=**}'));

      // Check mime type helpers
      expect(content, contains('isImage()'));
      expect(content, contains('isVideo()'));
      expect(content, contains('isAudio()'));
      expect(content, contains('isDocument()'));

      // Check size restrictions
      expect(content, contains('10 * 1024 * 1024')); // 10MB
      expect(content, contains('15 * 1024 * 1024')); // 15MB
      expect(content, contains('25 * 1024 * 1024')); // 25MB
      expect(content, contains('50 * 1024 * 1024')); // 50MB
    });

    test('firestore.rules is up to date with rich media chat and driver document verification', () {
      final file = File('firestore.rules');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      expect(content, contains("rules_version = '2'"));
      expect(content, contains('service cloud.firestore'));

      // Check rich media chat rules
      expect(content, contains('match /messages/{messageId}'));
      expect(content, contains('mediaUrl'));
      expect(content, contains('mediaType'));

      // Check driver document verification rules
      expect(content, contains('match /documents/{docId}'));
      expect(content, contains('isValidDriverDocument'));
    });

    test('database.rules.json has valid JSON syntax and rules', () {
      final file = File('database.rules.json');
      expect(file.existsSync(), isTrue);

      final content = file.readAsStringSync();
      final parsed = jsonDecode(content) as Map<String, dynamic>;
      expect(parsed.containsKey('rules'), isTrue);
      final rules = parsed['rules'] as Map<String, dynamic>;
      expect(rules.containsKey('driver_locations'), isTrue);
      expect(rules.containsKey('ride_tracking'), isTrue);
    });
  });
}
