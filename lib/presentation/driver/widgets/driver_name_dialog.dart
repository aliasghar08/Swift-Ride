import 'package:flutter/material.dart';
import '../../../core/provider/custom_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../providers/auth_provider.dart';

/// Checks if a driver's name is missing, empty, or a default placeholder.
bool isDefaultDriverName(String? name) {
  if (name == null) return true;
  final trimmed = name.trim().toLowerCase();
  if (trimmed.isEmpty) return true;
  const defaultNames = {
    'swiftride user',
    'swift ride user',
    'driver',
    'driver user',
    'guest user',
    'user',
    'rider',
    'unnamed driver',
  };
  return defaultNames.contains(trimmed);
}

/// Modal dialog prompting the driver to enter their official full name.
/// Persists directly to Firestore, updates [AuthProvider], and refreshes UI.
class DriverNameDialog extends StatefulWidget {
  final String? initialName;

  const DriverNameDialog({super.key, this.initialName});

  static Future<bool?> show(
    BuildContext context, {
    String? currentName,
    bool barrierDismissible = false,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => DriverNameDialog(initialName: currentName),
    );
  }

  @override
  State<DriverNameDialog> createState() => _DriverNameDialogState();
}

class _DriverNameDialogState extends State<DriverNameDialog> {
  late final TextEditingController _nameController;
  bool _isSaving = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialName;
    _nameController = TextEditingController(
      text: (initial != null && !isDefaultDriverName(initial)) ? initial : '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final raw = _nameController.text.trim();
    if (raw.length < 3) {
      setState(() => _errorMessage = 'Please enter at least 3 characters.');
      return;
    }
    if (isDefaultDriverName(raw)) {
      setState(() => _errorMessage = 'Please enter your actual legal full name.');
      return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
      await auth.updateFullName(raw);

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text('Profile updated: $raw')),
              ],
            ),
            backgroundColor: AppTheme.emeraldGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _errorMessage = 'Failed to save name: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: !widget.initialName.let((n) => isDefaultDriverName(n)),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Icon Header
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppTheme.emeraldGreen.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.badge_rounded,
                    color: AppTheme.emeraldGreen,
                    size: 30,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Driver Identity Verification',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppTheme.darkNavy,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please enter your official full name as shown on your CNIC / Driving License. Riders will see this name on live trips and receipts.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white70 : AppTheme.slateMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameController,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Full Legal Name',
                  hintText: 'e.g., Muhammad Ali Khan',
                  prefixIcon: const Icon(Icons.person_outline_rounded),
                  errorText: _errorMessage,
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: isDark ? Colors.white24 : Colors.black12,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(
                      color: AppTheme.emeraldGreen,
                      width: 2,
                    ),
                  ),
                ),
                onSubmitted: (_) => _handleSave(),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  if (!isDefaultDriverName(widget.initialName)) ...[
                    Expanded(
                      child: TextButton(
                        onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          'Cancel',
                          style: TextStyle(
                            color: isDark ? Colors.white60 : AppTheme.slateMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _handleSave,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.emeraldGreen,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Save Name',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _ObjectExt<T> on T {
  R let<R>(R Function(T it) op) => op(this);
}
