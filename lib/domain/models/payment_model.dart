import 'payment_method_type.dart';

class PaymentRecord {
  final String id;
  final String rideId;
  final String userId;
  final double amount;
  final PaymentMethodType method;
  final String status;
  final String? stripePaymentIntentId;
  final DateTime createdAt;

  const PaymentRecord({
    required this.id,
    required this.rideId,
    required this.userId,
    required this.amount,
    required this.method,
    required this.status,
    this.stripePaymentIntentId,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'rideId': rideId,
        'userId': userId,
        'amount': amount,
        'method': method.name.toUpperCase(),
        'status': status,
        'stripePaymentIntentId': stripePaymentIntentId,
        'createdAt': createdAt.toIso8601String(),
      };

  factory PaymentRecord.fromMap(Map<String, dynamic> map, {String? docId}) {
    return PaymentRecord(
      id: docId ?? map['id'] ?? '',
      rideId: map['rideId'] ?? '',
      userId: map['userId'] ?? '',
      amount: (map['amount'] as num?)?.toDouble() ?? 0.0,
      method: PaymentMethodType.fromString(map['method']),
      status: map['status'] ?? 'pending',
      stripePaymentIntentId: map['stripePaymentIntentId'],
      createdAt: map['createdAt'] != null
          ? DateTime.tryParse(map['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
