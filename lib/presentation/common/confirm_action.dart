import 'package:flutter/material.dart';

import '../../core/theme/design_tokens.dart';

/// A single, consistent confirmation step for destructive or irreversible
/// actions.
///
/// Returns `true` **only** when the user explicitly confirms. Dismissing the
/// dialog — tapping outside, the back gesture, or the cancel button — resolves
/// to `false`, so the safe outcome is always the default. Callers should treat
/// a `false` result as "do nothing".
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  String cancelLabel = 'Cancel',
  bool destructive = false,
  IconData? icon,
}) async {
  final c = AppColors.of(context);

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: Radii.lgAll),
      icon: icon == null
          ? null
          : Icon(icon, size: 28, color: destructive ? c.danger : c.info),
      title: Text(
        title,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 17,
          color: c.textPrimary,
        ),
      ),
      content: Text(
        message,
        textAlign: TextAlign.center,
        style: TextStyle(color: c.textSecondary, height: 1.4, fontSize: 13.5),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(
            cancelLabel,
            style: TextStyle(color: c.textMuted, fontWeight: FontWeight.w600),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? c.danger : c.info,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: Radii.smAll),
          ),
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  return result ?? false;
}
