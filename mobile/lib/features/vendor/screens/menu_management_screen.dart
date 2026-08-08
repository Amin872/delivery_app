import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../customer/screens/vendor_menu_screen.dart' show vendorMenuProvider;

class MenuManagementScreen extends ConsumerWidget {
  const MenuManagementScreen({required this.vendorId, super.key});

  final String vendorId;

  Future<void> _openForm(BuildContext context, {MenuItem? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _MenuItemForm(vendorId: vendorId, existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, MenuItem item) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        content: Text(l10n.deleteMenuItemConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancelButton),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(firestoreServiceProvider).deleteMenuItem(vendorId, item.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(vendorMenuProvider(vendorId));
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat.currency(
      locale: Localizations.localeOf(context).toString(),
      name: 'SYP',
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuManagementTitle),
        actions: const [LanguageToggleButton()],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addMenuItemTitle,
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
      body: menuAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(l10n.noMenuItemsMessage));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              return Card(
                child: ListTile(
                  title: Text(
                    item.name,
                    style: item.available
                        ? null
                        : TextStyle(color: Theme.of(context).disabledColor),
                  ),
                  subtitle: Text(currencyFormat.format(item.price)),
                  leading: Switch(
                    value: item.available,
                    onChanged: (value) => ref.read(firestoreServiceProvider).updateMenuItem(
                          vendorId,
                          MenuItem(
                            id: item.id,
                            vendorId: vendorId,
                            name: item.name,
                            price: item.price,
                            imageUrl: item.imageUrl,
                            available: value,
                          ),
                        ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: l10n.editTooltip,
                        onPressed: () => _openForm(context, existing: item),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        tooltip: l10n.deleteTooltip,
                        onPressed: () => _confirmDelete(context, ref, item),
                      ),
                    ],
                  ),
                ),
              ).staggeredEntrance(index);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text(localizedErrorMessage(context, error))),
      ),
    );
  }
}

class _MenuItemForm extends ConsumerStatefulWidget {
  const _MenuItemForm({required this.vendorId, this.existing});

  final String vendorId;
  final MenuItem? existing;

  @override
  ConsumerState<_MenuItemForm> createState() => _MenuItemFormState();
}

class _MenuItemFormState extends ConsumerState<_MenuItemForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _priceController;
  late bool _available;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // `widget` isn't available at field-initializer time in a State class,
    // so these are populated here rather than inline at declaration.
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _priceController =
        TextEditingController(text: widget.existing?.price.toStringAsFixed(2) ?? '');
    _available = widget.existing?.available ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final item = MenuItem(
        id: widget.existing?.id ?? '',
        vendorId: widget.vendorId,
        name: _nameController.text.trim(),
        price: double.parse(_priceController.text.trim()),
        imageUrl: widget.existing?.imageUrl,
        available: _available,
      );
      final service = ref.read(firestoreServiceProvider);
      if (widget.existing == null) {
        await service.addMenuItem(widget.vendorId, item);
      } else {
        await service.updateMenuItem(widget.vendorId, item);
      }
      if (mounted) Navigator.of(context).pop();
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
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.existing == null ? l10n.addMenuItemTitle : l10n.editMenuItemTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.itemNameLabel),
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _priceController,
              decoration: InputDecoration(labelText: l10n.priceLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed <= 0) return l10n.invalidPriceError;
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.availableLabel),
              value: _available,
              onChanged: (value) => setState(() => _available = value),
            ),
            const SizedBox(height: 12),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            GradientButton(
              onPressed: _isSubmitting ? null : _save,
              child: _isSubmitting
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onPrimary,
                      ),
                    )
                  : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}
