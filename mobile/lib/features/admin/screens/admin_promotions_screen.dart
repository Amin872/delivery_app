import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/approval_status.dart';
import '../../../models/promotion.dart';
import '../../../models/vendor.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_scaffold.dart';
import 'admin_vendors_screen.dart' show allVendorsProvider;
import '../../../core/widgets/state_views.dart';

final allPromotionsProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllPromotions();
});

/// The stores a promotion's CTA may link to: approved vendors only (the
/// customer carousel can only open a store it can show), by name. The CTA
/// contract itself is unchanged — `ctaAction` stores the chosen vendor's id
/// (see [Promotion.ctaAction] and PromoBannerCarousel).
List<Vendor> ctaVendorChoices(List<Vendor> vendors) {
  return vendors.where((vendor) => vendor.approvalStatus == ApprovalStatus.approved).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

/// Why a CTA (button label + linked store) can't be saved — a pure enum so
/// [validatePromotionCta] stays BuildContext-free and unit-testable.
enum PromotionCtaError { incomplete, unavailableVendor }

/// The button only shows when both a label and a store are set, so they're
/// required together (or both left empty); a linked store must be one of
/// [ctaVendorChoices] in [vendors]. [vendors] null (not loaded) can't
/// confirm any store, so a selected one is rejected rather than trusted.
PromotionCtaError? validatePromotionCta({
  required String? label,
  required String? vendorId,
  required List<Vendor>? vendors,
}) {
  final hasLabel = label != null && label.trim().isNotEmpty;
  if (vendorId == null) return hasLabel ? PromotionCtaError.incomplete : null;
  if (vendors == null || !ctaVendorChoices(vendors).any((vendor) => vendor.id == vendorId)) {
    return PromotionCtaError.unavailableVendor;
  }
  return hasLabel ? null : PromotionCtaError.incomplete;
}

/// Admin CRUD screen for `promotions/{promotionId}` — the content behind
/// the customer Home screen's [PromoBannerCarousel]. Mirrors
/// MenuManagementScreen's list + bottom-sheet-form + two-phase
/// (create-doc, upload-media, update-doc) save pattern rather than
/// inventing a new admin UI shape.
class AdminPromotionsScreen extends ConsumerWidget {
  const AdminPromotionsScreen({super.key});

  Future<void> _openForm(BuildContext context, {Promotion? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _PromotionForm(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, Promotion promotion) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      message: l10n.deletePromotionConfirmMessage,
      isDestructive: true,
    );
    if (confirmed != true || !context.mounted) return;
    HapticFeedback.lightImpact();
    await runAdminWrite(
      context,
      () => ref.read(firestoreServiceProvider).deletePromotion(promotion.id),
      successMessage: l10n.promotionDeletedMessage,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final promotionsAsync = ref.watch(allPromotionsProvider);
    final l10n = AppLocalizations.of(context)!;

    // Inside the shared AdminScaffold (admin theme + nav). It has no
    // floatingActionButton slot, so "Add" sits in a row above the list -
    // the same inline-add pattern AdminLocationsScreen uses.
    return AdminScaffold(
      title: l10n.adminPromotionsTitle,
      selected: AdminDestination.promotions,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton.filled(
              icon: const Icon(Icons.add),
              tooltip: l10n.addPromotionTitle,
              onPressed: () => _openForm(context),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: promotionsAsync.animatedWhen(
              data: (promotions) {
                if (promotions.isEmpty) {
                  return EmptyState(message: l10n.noPromotionsMessage);
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  itemCount: promotions.length,
                  itemBuilder: (context, index) {
                    final promotion = promotions[index];
                    return _PromotionCard(
                      key: ValueKey('admin_promotion_${promotion.id}'),
                      promotion: promotion,
                      onEdit: () => _openForm(context, existing: promotion),
                      onDelete: () => _confirmDelete(context, ref, promotion),
                      onSetEnabled: (enabled) {
                        HapticFeedback.selectionClick();
                        return runAdminWrite(
                          context,
                          () => ref.read(firestoreServiceProvider).setPromotionEnabled(promotion.id, enabled),
                        );
                      },
                    ).staggeredEntrance(index);
                  },
                );
              },
              loading: () => const ListSkeletonLoader(),
              error: (error, _) => ErrorState(error: error, onRetry: () => ref.invalidate(allPromotionsProvider)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _PromotionAction { edit, delete }

const _thumbnailSize = 48.0;

/// One promotion: thumbnail, title (full remaining width — edit/delete sit
/// in a small overflow menu) and its display order, with the enable switch
/// always visible on its own row so a 320px phone never squeezes the title.
class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    required this.promotion,
    required this.onEdit,
    required this.onDelete,
    required this.onSetEnabled,
    super.key,
  });

  final Promotion promotion;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Future<bool> Function(bool enabled) onSetEnabled;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final hasImage = promotion.mediaType == PromotionMediaType.image && promotion.mediaUrl.isNotEmpty;

    return Card(
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.xs),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                hasImage
                    ? AppNetworkImage(
                        imageUrl: promotion.mediaUrl,
                        width: _thumbnailSize,
                        height: _thumbnailSize,
                        borderRadius: AppRadius.small,
                      )
                    : Container(
                        width: _thumbnailSize,
                        height: _thumbnailSize,
                        decoration: const BoxDecoration(
                          color: VendorPalette.surfaceElevated,
                          borderRadius: AppRadius.small,
                        ),
                        child: Icon(
                          promotion.mediaType == PromotionMediaType.video
                              ? Icons.videocam_outlined
                              : Icons.campaign_outlined,
                          color: VendorPalette.textMuted,
                        ),
                      ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promotion.title?.isNotEmpty == true ? promotion.title! : l10n.promotionTitleFieldLabel,
                        style: textTheme.titleSmall?.copyWith(
                          color: promotion.enabled ? null : VendorPalette.textSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '${l10n.promotionOrderFieldLabel}: ${promotion.order}',
                        style: textTheme.bodySmall?.copyWith(color: VendorPalette.textSecondary),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<_PromotionAction>(
                  key: ValueKey('admin_promotion_actions_${promotion.id}'),
                  tooltip: l10n.vendorMoreActionsTooltip,
                  onSelected: (action) => switch (action) {
                    _PromotionAction.edit => onEdit(),
                    _PromotionAction.delete => onDelete(),
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _PromotionAction.edit,
                      child: AdminMenuItemLabel(icon: Icons.edit_outlined, label: l10n.editTooltip),
                    ),
                    PopupMenuItem(
                      value: _PromotionAction.delete,
                      child: AdminMenuItemLabel(
                        icon: Icons.delete_outline,
                        label: l10n.deleteTooltip,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.promotionEnabledLabel,
                    style: textTheme.bodyMedium?.copyWith(color: VendorPalette.textSecondary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                AdminAsyncSwitch(
                  key: ValueKey('admin_promotion_enabled_${promotion.id}'),
                  value: promotion.enabled,
                  tooltip: l10n.promotionEnabledLabel,
                  onChanged: onSetEnabled,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionForm extends ConsumerStatefulWidget {
  const _PromotionForm({this.existing});

  final Promotion? existing;

  @override
  ConsumerState<_PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends ConsumerState<_PromotionForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ctaLabelController;
  late final TextEditingController _orderController;
  late bool _enabled;
  late PromotionMediaType _mediaType;
  String? _ctaVendorId;
  File? _pickedMedia;
  // Id of the doc a previous, partly failed save of a NEW promotion already
  // created — a retry finishes that doc instead of creating a second one.
  String? _createdId;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _ctaLabelController = TextEditingController(text: existing?.ctaLabel ?? '');
    _orderController = TextEditingController(text: (existing?.order ?? 0).toString());
    _enabled = existing?.enabled ?? true;
    _mediaType = existing?.mediaType ?? PromotionMediaType.image;
    final ctaAction = existing?.ctaAction?.trim();
    _ctaVendorId = (ctaAction == null || ctaAction.isEmpty) ? null : ctaAction;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _ctaLabelController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  Future<void> _pickMedia() async {
    final picker = ImagePicker();
    final picked = _mediaType == PromotionMediaType.image
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await picker.pickVideo(source: ImageSource.gallery);
    if (picked != null) setState(() => _pickedMedia = File(picked.path));
  }

  // Same two-phase save as MenuManagementScreen's _MenuItemForm: a brand-new
  // promotion needs a Firestore doc id before media can be uploaded to
  // promotions/{promotionId}/{fileName}, so create (with a placeholder
  // mediaUrl) first, then upload, then write the real mediaUrl. The
  // placeholder doc is created disabled, so if the upload fails customers
  // never see a promotion with no media; the final write sets the real
  // enabled state.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (widget.existing == null && _pickedMedia == null) {
      setState(() {
        final l10n = AppLocalizations.of(context)!;
        _errorMessage = l10n.selectMediaRequiredError;
      });
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final title = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      final ctaLabel = _ctaLabelController.text.trim().isEmpty ? null : _ctaLabelController.text.trim();
      final order = int.parse(_orderController.text.trim());

      final promotionId = widget.existing?.id ??
          _createdId ??
          await firestore.addPromotion(
            Promotion(
              id: '',
              title: title,
              description: description,
              mediaUrl: '',
              mediaType: _mediaType,
              ctaLabel: ctaLabel,
              ctaAction: _ctaVendorId,
              order: order,
              enabled: false,
            ),
          );
      _createdId = widget.existing == null ? promotionId : null;

      var mediaUrl = widget.existing?.mediaUrl ?? '';
      if (_pickedMedia != null) {
        final fileName = _mediaType == PromotionMediaType.image ? 'media.jpg' : 'media.mp4';
        mediaUrl = await ref.read(storageServiceProvider).uploadPromotionMedia(promotionId, _pickedMedia!, fileName);
      }

      await firestore.updatePromotion(
        Promotion(
          id: promotionId,
          title: title,
          description: description,
          mediaUrl: mediaUrl,
          mediaType: _mediaType,
          ctaLabel: ctaLabel,
          ctaAction: _ctaVendorId,
          order: order,
          enabled: _enabled,
        ),
      );
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.promotionSavedMessage));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateCta(List<Vendor>? vendors, AppLocalizations l10n) {
    return switch (validatePromotionCta(label: _ctaLabelController.text, vendorId: _ctaVendorId, vendors: vendors)) {
      null => null,
      PromotionCtaError.incomplete => l10n.ctaIncompleteError,
      PromotionCtaError.unavailableVendor => l10n.ctaVendorUnavailableError,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final vendorsAsync = ref.watch(allVendorsProvider);
    final vendors = vendorsAsync.valueOrNull;
    final choices = ctaVendorChoices(vendors ?? const <Vendor>[]);
    // The saved store stays selectable even if it's no longer approved (or
    // not loaded yet), so opening the form never silently drops it; the
    // validator then asks for a valid one.
    final selectedId = _ctaVendorId;
    final keepsStaleChoice = selectedId != null && !choices.any((vendor) => vendor.id == selectedId);
    String staleLabel() {
      for (final vendor in vendors ?? const <Vendor>[]) {
        if (vendor.id == selectedId) return vendor.name;
      }
      return l10n.unknownVendorOption;
    }

    return SingleChildScrollView(
      key: const ValueKey('admin_promotion_form'),
      padding: const EdgeInsets.all(AppSpacing.xxl),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null ? l10n.addPromotionTitle : l10n.editPromotionTitle,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            SegmentedButton<PromotionMediaType>(
              segments: [
                ButtonSegment(
                  value: PromotionMediaType.image,
                  label: Text(l10n.mediaTypeImageLabel),
                  icon: const Icon(Icons.image_outlined),
                ),
                ButtonSegment(
                  value: PromotionMediaType.video,
                  label: Text(l10n.mediaTypeVideoLabel),
                  icon: const Icon(Icons.videocam_outlined),
                ),
              ],
              selected: {_mediaType},
              onSelectionChanged: (selection) => setState(() {
                _mediaType = selection.first;
                _pickedMedia = null;
              }),
            ),
            const SizedBox(height: AppSpacing.md),
            _MediaPickerPreview(
              mediaType: _mediaType,
              networkUrl: widget.existing?.mediaUrl,
              localFile: _pickedMedia,
              onTap: _pickMedia,
            ),
            const SizedBox(height: AppSpacing.lg),
            TextFormField(
              controller: _titleController,
              decoration: InputDecoration(labelText: l10n.promotionTitleFieldLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(labelText: l10n.promotionDescriptionFieldLabel),
              maxLines: 2,
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _ctaLabelController,
              decoration: InputDecoration(labelText: l10n.ctaLabelFieldLabel),
            ),
            const SizedBox(height: AppSpacing.md),
            DropdownButtonFormField<String?>(
              key: const ValueKey('admin_promotion_cta_vendor'),
              initialValue: selectedId,
              isExpanded: true,
              decoration: InputDecoration(labelText: l10n.ctaActionFieldLabel),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.ctaNoVendorOption, overflow: TextOverflow.ellipsis),
                ),
                for (final vendor in choices)
                  DropdownMenuItem<String?>(
                    value: vendor.id,
                    child: Text(vendor.name, overflow: TextOverflow.ellipsis),
                  ),
                if (keepsStaleChoice)
                  DropdownMenuItem<String?>(
                    value: selectedId,
                    child: Text(staleLabel(), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (value) => setState(() => _ctaVendorId = value),
              validator: (_) => _validateCta(vendors, l10n),
            ),
            const SizedBox(height: AppSpacing.md),
            TextFormField(
              controller: _orderController,
              decoration: InputDecoration(labelText: l10n.promotionOrderFieldLabel),
              keyboardType: TextInputType.number,
              validator: (value) {
                final parsed = int.tryParse(value?.trim() ?? '');
                if (parsed == null || parsed < 0) return l10n.invalidOrderError;
                return null;
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.promotionEnabledLabel),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: AppSpacing.md),
            if (_errorMessage != null) ...[
              Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: AppSpacing.sm),
            ],
            GradientButton(
              // Wait for the store list, so a linked store can be checked.
              onPressed: _isSubmitting || vendorsAsync.isLoading ? null : _save,
              child: _isSubmitting ? buttonSpinner(Theme.of(context).colorScheme.onPrimary) : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tap-to-pick preview for the form's media field: the picked local file,
/// else the saved image through the shared [AppNetworkImage] (loading
/// shimmer and broken-URL fallback), else a placeholder. A picked/saved
/// video shows an icon only (no thumbnail decoding).
class _MediaPickerPreview extends StatelessWidget {
  const _MediaPickerPreview({required this.mediaType, required this.onTap, this.networkUrl, this.localFile});

  final PromotionMediaType mediaType;
  final VoidCallback onTap;
  final String? networkUrl;
  final File? localFile;

  static const _height = 120.0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isImage = mediaType == PromotionMediaType.image;
    final hasLocalImage = localFile != null && isImage;
    final hasNetworkImage = localFile == null && isImage && (networkUrl?.isNotEmpty ?? false);

    final Widget content;
    if (hasLocalImage) {
      content = Image.file(localFile!, fit: BoxFit.cover, width: double.infinity, height: _height);
    } else if (hasNetworkImage) {
      content = AppNetworkImage(imageUrl: networkUrl!, width: double.infinity, height: _height);
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              localFile != null
                  ? Icons.videocam_outlined
                  : (isImage ? Icons.add_photo_alternate_outlined : Icons.video_call_outlined),
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: AppSpacing.xs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Text(
                localFile != null ? localFile!.uri.pathSegments.last : l10n.selectMediaLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label: l10n.selectMediaLabel,
      child: Material(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: AppRadius.large,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(height: _height, width: double.infinity, child: content),
        ),
      ),
    );
  }
}
