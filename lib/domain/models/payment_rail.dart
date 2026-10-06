import 'package:flutter/material.dart';

/// A way a rider can pay for a trip.
///
/// [isConfigured] reflects whether the rail is actually integrated end to end.
/// The picker previously offered "Credit / Debit Card (Stripe)", "Apple Pay" and
/// "Google Pay", none of which had any integration behind them — and Stripe
/// cannot onboard a Pakistan-based entity at all. Choosing one changed a label
/// and nothing else, so the rider believed they had set up a card payment that
/// could never happen.
///
/// Unconfigured rails are shown but not selectable, so the gap is visible rather
/// than disguised.
enum PaymentRail {
  cash(
    id: 'cash',
    label: 'Cash to Driver',
    description: 'Pay the driver directly at the end of the trip',
    icon: Icons.payments_outlined,
    isConfigured: true,
  ),
  jazzcash(
    id: 'jazzcash',
    label: 'JazzCash',
    description: 'Mobile wallet',
    icon: Icons.account_balance_wallet_outlined,
    isConfigured: false,
  ),
  easypaisa(
    id: 'easypaisa',
    label: 'Easypaisa',
    description: 'Mobile wallet',
    icon: Icons.account_balance_wallet_outlined,
    isConfigured: false,
  ),
  raast(
    id: 'raast',
    label: 'Raast',
    description: 'Instant bank transfer',
    icon: Icons.account_balance_outlined,
    isConfigured: false,
  ),
  card(
    id: 'card',
    label: 'Debit / Credit Card',
    description: 'Visa and Mastercard',
    icon: Icons.credit_card_outlined,
    isConfigured: false,
  );

  const PaymentRail({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.isConfigured,
  });

  /// Stable identifier stored on the ride document.
  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// True only when the rail genuinely works today.
  final bool isConfigured;

  /// The rail a rider gets by default, and the only one that currently works.
  static const PaymentRail fallback = PaymentRail.cash;

  static PaymentRail fromId(String? id) {
    if (id == null) return fallback;
    for (final rail in PaymentRail.values) {
      if (rail.id == id) return rail;
    }
    return fallback;
  }
}
