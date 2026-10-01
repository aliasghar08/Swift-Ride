enum SubscriptionStatus {
  active,
  inactive,
  trial;

  static SubscriptionStatus fromString(String? val) {
    switch (val?.toUpperCase()) {
      case 'ACTIVE':
        return SubscriptionStatus.active;
      case 'INACTIVE':
        return SubscriptionStatus.inactive;
      default:
        return SubscriptionStatus.trial;
    }
  }

  String toDbString() => name.toUpperCase();
}

enum SubscriptionPlan {
  daily,
  monthly,
  yearly;

  double get price {
    switch (this) {
      case SubscriptionPlan.daily:
        return 1.00;
      case SubscriptionPlan.monthly:
        return 15.00;
      case SubscriptionPlan.yearly:
        return 150.00;
    }
  }
}
