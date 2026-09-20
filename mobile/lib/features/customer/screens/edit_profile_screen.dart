import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

final _phonePattern = RegExp(r'^[0-9+\-\s]{7,}$');

/// Edits the mutable fields of the signed-in customer's `users/{uid}` doc —
/// display name and phone number. Email/role are intentionally not editable
/// here: email changes go through Firebase Auth (a separate, unbuilt flow),
/// and role is pinned server-side (see firestore.rules' users update rule).
///
/// Same [VendorPalette] theme as [PersonalInfoScreen], which pushes this
/// screen, so the edit flow doesn't visually jump to a different app.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({required this.appUser, super.key});

  final AppUser appUser;

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.appUser.displayName);
  late final _phoneController = TextEditingController(text: widget.appUser.phoneNumber ?? '');
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    try {
      final phone = _phoneController.text.trim();
      await ref.read(firestoreServiceProvider).updateUserProfile(
            widget.appUser.id,
            displayName: _nameController.text.trim(),
            phoneNumber: phone.isEmpty ? null : phone,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(buildAppSnackBar(colorScheme, l10n.profileUpdatedMessage));
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final colorScheme = vendorTheme.colorScheme;

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.editProfileTitle),
        ),
        body: ResponsiveCenter(
          child: CenteredScrollBody(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextFormField(
                    key: const ValueKey('edit_profile_name_field'),
                    controller: _nameController,
                    decoration: InputDecoration(labelText: l10n.displayNameLabel),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const ValueKey('edit_profile_phone_field'),
                    controller: _phoneController,
                    decoration: InputDecoration(labelText: l10n.phoneNumberLabel),
                    keyboardType: TextInputType.phone,
                    validator: (value) {
                      final trimmed = value?.trim() ?? '';
                      if (trimmed.isEmpty) return null;
                      if (!_phonePattern.hasMatch(trimmed)) return l10n.invalidPhoneFormatError;
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_errorMessage!, style: TextStyle(color: colorScheme.error)),
                    ),
                  GradientButton(
                    key: const ValueKey('edit_profile_submit_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [VendorPalette.primaryCyan, VendorPalette.secondaryCyan],
                    ),
                    child: _isSubmitting
                        ? buttonSpinner(colorScheme.onPrimary)
                        : Text(l10n.saveButton),
                  ),
                ],
              ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.05, end: 0),
            ),
          ),
        ),
      ),
    );
  }
}
