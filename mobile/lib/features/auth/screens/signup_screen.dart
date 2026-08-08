import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/l10n/enum_labels.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/app_user.dart';
import '../providers/auth_provider.dart';

// Admin accounts are promoted out-of-band (see the comment on UserRole in
// app_user.dart) — never offer `admin` as a self-service signup choice.
const _selfServiceRoles = [UserRole.customer, UserRole.driver, UserRole.vendor];

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _phonePattern = RegExp(r'^[0-9+\-\s]{7,}$');

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _phoneController = TextEditingController();
  UserRole _role = UserRole.customer;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).signUp(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            displayName: _nameController.text.trim(),
            role: _role,
            phoneNumber: _phoneController.text.trim(),
          );
    } catch (error) {
      if (mounted) {
        setState(() => _errorMessage = localizedErrorMessage(context, error));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(l10n.createAccountTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppGradients.surface(colorScheme)),
        child: SafeArea(
          child: CenteredScrollBody(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(labelText: l10n.displayNameLabel),
                validator: (value) =>
                    (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: l10n.emailLabel),
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return l10n.requiredFieldError;
                  if (!_emailPattern.hasMatch(trimmed)) return l10n.invalidEmailFormatError;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: l10n.passwordLabel),
                obscureText: true,
                validator: (value) {
                  if (value == null || value.isEmpty) return l10n.requiredFieldError;
                  if (value.length < 6) return l10n.passwordTooShortError;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(labelText: l10n.phoneNumberLabel),
                keyboardType: TextInputType.phone,
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) return l10n.requiredFieldError;
                  if (!_phonePattern.hasMatch(trimmed)) return l10n.invalidPhoneFormatError;
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<UserRole>(
                initialValue: _role,
                decoration: InputDecoration(labelText: l10n.roleLabel),
                items: _selfServiceRoles
                    .map((role) => DropdownMenuItem(
                          value: role,
                          child: Text(userRoleLabel(context, role)),
                        ))
                    .toList(),
                onChanged: (role) => setState(() => _role = role!),
              ),
              const SizedBox(height: 24),
              if (_errorMessage != null)
                Text(
                  _errorMessage!,
                  style: TextStyle(color: colorScheme.error),
                ),
              GradientButton(
                onPressed: _isSubmitting ? null : _submit,
                child: _isSubmitting
                    ? buttonSpinner(colorScheme.onPrimary)
                    : Text(l10n.createAccountTitle),
              ),
              TextButton(
                onPressed: () => context.go('/login'),
                child: Text(l10n.alreadyHaveAccountButton),
              ),
                ],
              ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
            ),
          ),
        ),
      ),
    );
  }
}
