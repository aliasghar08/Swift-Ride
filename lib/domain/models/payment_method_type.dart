enum PaymentMethodType {
  card,
  applePay,
  googlePay,
  cash;

  String get displayName {
    switch (this) {
      case PaymentMethodType.card:
        return 'Credit / Debit Card (Stripe)';
      case PaymentMethodType.applePay:
        return 'Apple Pay';
      case PaymentMethodType.googlePay:
        return 'Google Pay';
      case PaymentMethodType.cash:
        return 'Cash to Driver';
    }
  }

  static PaymentMethodType fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'APPLEPAY':
      case 'APPLE_PAY':
        return PaymentMethodType.applePay;
      case 'GOOGLEPAY':
      case 'GOOGLE_PAY':
        return PaymentMethodType.googlePay;
      case 'CASH':
        return PaymentMethodType.cash;
      default:
        return PaymentMethodType.card;
    }
  }
}
