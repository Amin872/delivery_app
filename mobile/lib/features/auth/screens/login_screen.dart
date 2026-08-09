import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      await ref.read(authServiceProvider).signIn(
            email: _emailController.text.trim(),
            password: _passwordController.text,
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
        title: Text(l10n.signInTitle),
        actions: const [LanguageToggleButton()],
      ),
      body: Container(
        decoration: BoxDecoration(gradient: AppGradients.surface(colorScheme)),
        child: SafeArea(
          child: ResponsiveCenter(
            child: CenteredScrollBody(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
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
                      validator: (value) =>
                          (value == null || value.isEmpty) ? l10n.requiredFieldError : null,
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: TextButton(
                        onPressed: () => context.go('/forgot-password'),
                        child: Text(l10n.forgotPasswordButton),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_errorMessage != null)
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.error),
                      ),
                    GradientButton(
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? buttonSpinner(colorScheme.onPrimary)
                          : Text(l10n.signInTitle),
                    ),
                    TextButton(
                      onPressed: () => context.go('/signup'),
                      child: Text(l10n.createAccountNavButton),
                    ),
                  ],
                ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
