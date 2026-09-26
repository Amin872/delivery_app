import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/format/display_formatters.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/image_picker_avatar.dart';
import '../../../core/widgets/language_toggle_button.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../core/widgets/state_views.dart';
import '../../../core/widgets/status_badge.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../../../services/storage_service.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../customer/screens/vendor_menu_screen.dart' show vendorMenuProvider;

final storageServiceProvider = Provider<StorageService>((ref) => StorageService());

/// Thumbnail edge for a menu row (the old CircleAvatar's 40px, plus room
/// for a photo to actually read as food).
const double _thumbnailSize = 56;

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final menuAsync = ref.watch(vendorMenuProvider(vendorId));
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.menuManagementTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: const [LanguageToggleButton()],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: l10n.addMenuItemTitle,
        onPressed: () => _openForm(context),
        child: const Icon(Icons.add),
      ),
      body: ResponsiveCenter(
        child: menuAsync.animatedWhen(
          data: (items) {
            if (items.isEmpty) {
              return EmptyState(icon: Icons.restaurant_menu, message: l10n.noMenuItemsMessage);
            }
            return ListView.builder(
              // Bottom room so the last row's controls clear the FAB.
              padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.section + AppSpacing.xxxl),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _MenuItemCard(
                  key: ValueKey('menu_item_${item.id}'),
                  vendorId: vendorId,
                  item: item,
                  onEdit: () => _openForm(context, existing: item),
                ).staggeredEntrance(index);
              },
            );
          },
          loading: () => const ListSkeletonLoader(),
          error: (error, _) => ErrorState(error: error),
        ),
      ),
    );
  }
}

enum _MenuItemAction { edit, delete }

/// One dish: photo, then its name (with the full remaining width —
/// edit/delete sit in a small overflow menu) and an availability badge,
/// then the price beside the always-visible availability switch.
class _MenuItemCard extends ConsumerWidget {
  const _MenuItemCard({required this.vendorId, required this.item, required this.onEdit, super.key});

  final String vendorId;
  final MenuItem item;
  final VoidCallback onEdit;

  // Shared failure path for the row's writes: a localized message, never
  // the raw exception. (A failed write leaves the row in place, so its
  // context is still mounted to word the message.)
  Future<void> _guarded(BuildContext context, Future<void> Function() write) async {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      await write();
    } catch (error) {
      if (!context.mounted) return;
      messenger.showSnackBar(
        buildAppSnackBar(colorScheme, localizedErrorMessage(context, error), isError: true),
      );
    }
  }

  Future<void> _setAvailable(BuildContext context, WidgetRef ref, bool value) {
    HapticFeedback.selectionClick();
    // updateMenuItem writes via .set() (full overwrite, not .update()) —
    // every field not being changed here must be carried over explicitly,
    // especially orderCount: it's aggregated server-side by a Cloud
    // Function (see MenuItem's doc comment) and would silently reset to 0
    // if omitted.
    return _guarded(
      context,
      () => ref.read(firestoreServiceProvider).updateMenuItem(
            vendorId,
            MenuItem(
              id: item.id,
              vendorId: vendorId,
              name: item.name,
              price: item.price,
              imageUrl: item.imageUrl,
              available: value,
              description: item.description,
              section: item.section,
              orderCount: item.orderCount,
            ),
          ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(context, message: l10n.deleteMenuItemConfirmMessage);
    if (confirmed != true || !context.mounted) return;
    HapticFeedback.lightImpact();
    await _guarded(context, () => ref.read(firestoreServiceProvider).deleteMenuItem(vendorId, item.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final currencyFormat = ref.watch(currencyFormatProvider);
    final imageUrl = item.imageUrl;

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                imageUrl != null
                    ? AppNetworkImage(
                        imageUrl: imageUrl,
                        width: _thumbnailSize,
                        height: _thumbnailSize,
                        borderRadius: AppRadius.medium,
                      )
                    : Container(
                        width: _thumbnailSize,
                        height: _thumbnailSize,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest,
                          borderRadius: AppRadius.medium,
                        ),
                        child: Icon(Icons.fastfood_outlined, color: AppColors.textMuted(colorScheme)),
                      ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.name,
                        style: textTheme.titleSmall?.copyWith(
                          color: item.available ? null : AppColors.textSecondary(colorScheme),
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      StatusBadge(
                        label: item.available ? l10n.availableLabel : l10n.unavailableLabel,
                        tone: item.available ? StatusTone.success : StatusTone.neutral,
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_MenuItemAction>(
                  key: ValueKey('menu_item_actions_${item.id}'),
                  tooltip: l10n.vendorMoreActionsTooltip,
                  onSelected: (action) => switch (action) {
                    _MenuItemAction.edit => onEdit(),
                    _MenuItemAction.delete => _confirmDelete(context, ref),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _MenuItemAction.edit,
                      child: _MenuActionLabel(icon: Icons.edit_outlined, label: l10n.editTooltip),
                    ),
                    PopupMenuItem(
                      value: _MenuItemAction.delete,
                      child: _MenuActionLabel(
                        icon: Icons.delete_outline,
                        label: l10n.deleteTooltip,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            // Price and the availability switch share the card's full
            // width, so even an eight-digit price stays on one line.
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(currencyFormat.format(item.price), style: textTheme.titleSmall, maxLines: 1),
                    ),
                  ),
                ),
                Tooltip(
                  message: l10n.availableLabel,
                  child: Switch(
                    key: ValueKey('menu_item_available_${item.id}'),
                    value: item.available,
                    onChanged: (value) => _setAvailable(context, ref, value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuActionLabel extends StatelessWidget {
  const _MenuActionLabel({required this.icon, required this.label, this.color});

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: AppSizes.iconLarge, color: color),
        const SizedBox(width: AppSpacing.md),
        Expanded(child: Text(label, style: TextStyle(color: color))),
      ],
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
  late final TextEditingController _descriptionController;
  late final TextEditingController _sectionController;
  late bool _available;
  File? _pickedImage;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // `widget` isn't available at field-initializer time in a State class,
    // so these are populated here rather than inline at declaration.
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _priceController = TextEditingController(text: formatAmountForInput(widget.existing?.price));
    _descriptionController = TextEditingController(text: widget.existing?.description ?? '');
    _sectionController = TextEditingController(text: widget.existing?.section ?? '');
    _available = widget.existing?.available ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _priceController.dispose();
    _descriptionController.dispose();
    _sectionController.dispose();
    super.dispose();
  }

  // A newly picked image can't be uploaded to vendorImages/{vendorId}/menu_{itemId}.jpg
  // until the item has an id — for a brand-new item that means creating the
  // Firestore doc first (unimaged), then uploading and writing the imageUrl
  // in a second update. An existing item already has its id, so a picked
  // image there is uploaded before the single update that saves everything.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final name = _nameController.text.trim();
      final price = double.parse(_priceController.text.trim());
      final description =
          _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      final section = _sectionController.text.trim().isEmpty ? null : _sectionController.text.trim();
      final isNew = widget.existing == null;

      final itemId = isNew
          ? await firestore.addMenuItem(
              widget.vendorId,
              MenuItem(
                id: '',
                vendorId: widget.vendorId,
                name: name,
                price: price,
                available: _available,
                description: description,
                section: section,
              ),
            )
          : widget.existing!.id;

      var imageUrl = widget.existing?.imageUrl;
      if (_pickedImage != null) {
        imageUrl = await ref
            .read(storageServiceProvider)
            .uploadVendorImage(widget.vendorId, _pickedImage!, 'menu_$itemId.jpg');
      }

      // A brand-new item with no picked image is already fully saved by
      // addMenuItem above; an edit, or a new item that just got an image,
      // still needs this write. updateMenuItem writes via .set() (full
      // overwrite), so orderCount — aggregated server-side, see MenuItem's
      // doc comment — must be carried over from the existing item rather
      // than left at its default 0, or every edit would silently erase a
      // dish's popularity.
      if (!isNew || _pickedImage != null) {
        await firestore.updateMenuItem(
          widget.vendorId,
          MenuItem(
            id: itemId,
            vendorId: widget.vendorId,
            name: name,
            price: price,
            imageUrl: imageUrl,
            available: _available,
            description: description,
            section: section,
            orderCount: widget.existing?.orderCount ?? 0,
          ),
        );
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
    // Scrolls, so every field and the save button stay reachable with the
    // keyboard up, on a small phone, or at a large text scale.
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.addMenuItemTitle : l10n.editMenuItemTitle,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Center(
              child: ImagePickerAvatar(
                radius: 40,
                networkUrl: widget.existing?.imageUrl,
                localFile: _pickedImage,
                onPicked: (file) => setState(() => _pickedImage = file),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              key: const ValueKey('menu_item_name_field'),
              controller: _nameController,
              decoration: InputDecoration(labelText: l10n.itemNameLabel),
              textInputAction: TextInputAction.next,
              validator: (value) =>
                  (value == null || value.trim().isEmpty) ? l10n.requiredFieldError : null,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('menu_item_price_field'),
              controller: _priceController,
              decoration: InputDecoration(labelText: l10n.priceLabel),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textInputAction: TextInputAction.next,
              validator: (value) {
                final parsed = double.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed <= 0) return l10n.invalidPriceError;
                return null;
              },
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('menu_item_description_field'),
              controller: _descriptionController,
              decoration: InputDecoration(labelText: l10n.itemDescriptionLabel),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              key: const ValueKey('menu_item_section_field'),
              controller: _sectionController,
              decoration: InputDecoration(labelText: l10n.itemSectionFieldLabel),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.availableLabel),
              value: _available,
              onChanged: (value) => setState(() => _available = value),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_errorMessage != null) ...[
              Text(
                _errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            GradientButton(
              key: const ValueKey('menu_item_save_button'),
              onPressed: _isSubmitting ? null : _save,
              child: _isSubmitting
                  ? buttonSpinner(Theme.of(context).colorScheme.onPrimary)
                  : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}
