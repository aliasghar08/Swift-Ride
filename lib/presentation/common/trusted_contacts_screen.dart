import 'package:flutter/material.dart';

import '../../core/provider/custom_provider.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/design_tokens.dart';
import '../../domain/models/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../services/firestore/firestore_user_service.dart';

/// Lets a user manage the people notified when they raise an SOS.
///
/// These numbers are stored on the user document and resolved by the
/// `triggerSos` Cloud Function, which pushes to each contact's devices.
class TrustedContactsScreen extends StatefulWidget {
  const TrustedContactsScreen({super.key});

  @override
  State<TrustedContactsScreen> createState() => _TrustedContactsScreenState();
}

class _TrustedContactsScreenState extends State<TrustedContactsScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FirestoreUserService _userService = FirestoreUserService();

  List<String> _contacts = [];
  bool _isLoaded = false;
  bool _isSaving = false;
  String? _error;
  String? _fieldError;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_isLoaded) return;
    _isLoaded = true;
    _contacts = List<String>.from(
      CustomChangeNotifierProvider.of<AuthProvider>(context).currentUser.trustedContacts,
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  void _addContact() {
    final normalised = AppUser.normalizePhone(_phoneController.text);

    if (normalised == null) {
      setState(() => _fieldError = 'Enter a valid phone number, e.g. +923001234567.');
      return;
    }
    if (_contacts.contains(normalised)) {
      setState(() => _fieldError = 'That number is already in your trusted contacts.');
      return;
    }
    if (_contacts.length >= 5) {
      setState(() => _fieldError = 'You can add up to 5 trusted contacts.');
      return;
    }

    setState(() {
      _contacts = [..._contacts, normalised];
      _fieldError = null;
      _phoneController.clear();
    });
  }

  Future<void> _save() async {
    if (_isSaving) return;

    final auth = CustomChangeNotifierProvider.of<AuthProvider>(context);
    setState(() {
      _isSaving = true;
      _error = null;
    });

    final ok = await _userService.updateTrustedContacts(auth.currentUser.id, _contacts);

    if (!mounted) return;

    if (ok) {
      auth.updateUser(auth.currentUser.copyWith(trustedContacts: _contacts));
    }

    setState(() {
      _isSaving = false;
      _error = ok ? null : 'We could not save your trusted contacts. Please try again.';
    });

    if (ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trusted contacts saved.'),
          backgroundColor: AppTheme.emeraldGreen,
        ),
      );
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);

    return Scaffold(
      backgroundColor: c.canvas,
      appBar: AppBar(
        title: const Text('Trusted Contacts'),
        backgroundColor: c.surface,
        foregroundColor: c.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Spacing.lg),
          children: [
            Container(
              padding: const EdgeInsets.all(Spacing.md),
              decoration: BoxDecoration(
                color: c.surfaceRaised,
                borderRadius: Radii.mdAll,
                border: Border.all(color: c.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.shield_outlined, size: 18, color: c.info),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(
                      'When you trigger an emergency SOS during a trip, these people are '
                      'notified with your live location, alongside your driver. Contacts '
                      'need the SwiftRide app installed to receive the alert.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: Spacing.lg),

            Text(
              'Your contacts',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),

            if (_contacts.isEmpty)
              Container(
                padding: const EdgeInsets.all(Spacing.lg),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: Radii.mdAll,
                  border: Border.all(color: c.border),
                ),
                child: Text(
                  'No trusted contacts yet.',
                  style: TextStyle(fontSize: 13, color: c.textMuted),
                ),
              )
            else
              for (final contact in _contacts)
                Container(
                  margin: const EdgeInsets.only(bottom: Spacing.sm),
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: Radii.mdAll,
                    border: Border.all(color: c.border),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.person_outline, color: c.info),
                    title: Text(
                      contact,
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.textPrimary),
                    ),
                    // 48dp minimum, labelled for screen readers.
                    trailing: IconButton(
                      tooltip: 'Remove $contact',
                      icon: Icon(Icons.close, color: c.danger),
                      onPressed: _isSaving
                          ? null
                          : () => setState(() => _contacts =
                              _contacts.where((c0) => c0 != contact).toList()),
                    ),
                  ),
                ),

            const SizedBox(height: Spacing.lg),
            Text(
              'Add a contact',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: c.textPrimary),
            ),
            const SizedBox(height: Spacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _addContact(),
                    decoration: InputDecoration(
                      hintText: '+923001234567',
                      errorText: _fieldError,
                    ),
                  ),
                ),
                const SizedBox(width: Spacing.sm),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _addContact,
                    child: const Text('Add'),
                  ),
                ),
              ],
            ),

            if (_error != null) ...[
              const SizedBox(height: Spacing.md),
              Row(
                children: [
                  Icon(Icons.error_outline, size: 16, color: c.danger),
                  const SizedBox(width: Spacing.sm),
                  Expanded(
                    child: Text(_error!, style: TextStyle(fontSize: 12.5, color: c.danger)),
                  ),
                ],
              ),
            ],

            const SizedBox(height: Spacing.xxl),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save trusted contacts'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
