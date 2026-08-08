import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _isSubmitting = false;
  String? _resultMessage;
  bool _resultIsError = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _resultMessage = null;
    });
    final l10n = AppLocalizations.of(context)!;
    try {
      await ref
          .read(authServiceProvider)
          .sendPasswordResetEmail(_emailController.text.trim());
      if (mounted) {
        setState(() {
          _resultMessage = l10n.resetLinkSentMessage;
          _resultIsError = false;
        });
      }
    } catch (error) {
      // Never reveal whether an email is registered — a `user-not-found`
      // failure gets the same confirmation message as a real send.
      final cause = error is AppException ? error.cause : error;
      final isUserNotFound = cause is FirebaseAuthException && cause.code == 'user-not-found';
      if (!mounted) return;
      setState(() {
        _resultMessage =
            isUserNotFound ? l10n.resetLinkSentMessage : localizedErrorMessage(context, error);
        _resultIsError = !isUserNotFound;
      });
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
        title: Text(l10n.resetPasswordTitle),
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
                  Text(l10n.resetPasswordInstructions),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 24),
                  if (_resultMessage != null)
                    Text(
                      _resultMessage!,
                      style: TextStyle(
                        color: _resultIsError ? colorScheme.error : colorScheme.primary,
                      ),
                    ),
                  const SizedBox(height: 12),
                  GradientButton(
                    onPressed: _isSubmitting ? null : _submit,
                    child: _isSubmitting
                        ? buttonSpinner(colorScheme.onPrimary)
                        : Text(l10n.sendResetLinkButton),
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: Text(l10n.backToSignInButton),
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
