import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/centered_scroll_body.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/address.dart';
import 'customer_home_screen.dart' show firestoreServiceProvider;

/// Add or edit a single [DeliveryAddress] — one free-form multi-line text
/// field for the full address (no street/building/apartment/postal-code
/// fields, per this app's Syria-first addressing model), a short label, and
/// a "set as default" toggle. [address] null means "add new".
class EditAddressScreen extends ConsumerStatefulWidget {
  const EditAddressScreen({required this.customerId, this.address, super.key});

  final String customerId;
  final DeliveryAddress? address;

  @override
  ConsumerState<EditAddressScreen> createState() => _EditAddressScreenState();
}

class _EditAddressScreenState extends ConsumerState<EditAddressScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _labelController = TextEditingController(text: widget.address?.label ?? '');
  late final _addressController = TextEditingController(text: widget.address?.address ?? '');
  late bool _isDefault = widget.address?.isDefault ?? false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void dispose() {
    _labelController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final service = ref.read(firestoreServiceProvider);
      final existing = widget.address;
      if (existing == null) {
        await service.addAddress(
          widget.customerId,
          DeliveryAddress(
            id: '',
            label: _labelController.text.trim(),
            address: _addressController.text.trim(),
            isDefault: _isDefault,
          ),
        );
      } else {
        await service.updateAddress(
          widget.customerId,
          DeliveryAddress(
            id: existing.id,
            label: _labelController.text.trim(),
            address: _addressController.text.trim(),
            isDefault: existing.isDefault,
          ),
        );
        if (_isDefault && !existing.isDefault) {
          await service.setDefaultAddress(widget.customerId, existing.id);
        }
      }
      if (!mounted) return;
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
    final isEditing = widget.address != null;

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(isEditing ? l10n.editAddressTitle : l10n.addAddressButton),
        ),
        body: ResponsiveCenter(
          child: CenteredScrollBody(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextFormField(
                    key: const ValueKey('address_label_field'),
                    controller: _labelController,
                    decoration: InputDecoration(
                      labelText: l10n.addressLabelFieldLabel,
                      hintText: l10n.addressLabelHint,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextFormField(
                    key: const ValueKey('address_text_field'),
                    controller: _addressController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: InputDecoration(
                      labelText: l10n.deliveryAddressLabel,
                      hintText: l10n.addressFieldHint,
                      helperText: l10n.addressFieldHelperText,
                      helperMaxLines: 2,
                    ),
                    validator: (value) =>
                        (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  CheckboxListTile(
                    value: _isDefault,
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(l10n.setAsDefaultButton),
                    onChanged: (value) => setState(() => _isDefault = value ?? false),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.md),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: VendorPalette.textSecondary),
                      ),
                    ),
                  GradientButton(
                    key: const ValueKey('address_submit_button'),
                    onPressed: _isSubmitting ? null : _submit,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [VendorPalette.primaryCyan, VendorPalette.secondaryCyan],
                    ),
                    child: _isSubmitting
                        ? buttonSpinner(vendorTheme.colorScheme.onPrimary)
                        : Text(l10n.saveAddressButton),
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
