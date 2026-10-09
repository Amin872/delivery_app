import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/paging/paged_list_controller.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
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
import '../../../services/firestore_service.dart';
import '../../vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import '../widgets/admin_actions.dart';
import '../widgets/admin_paged_list.dart';
import '../widgets/admin_scaffold.dart';
import '../../../core/widgets/state_views.dart';

final allPromotionsProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllPromotions();
});

/// Why a CTA (button label + linked store) can't be saved — a pure enum so
/// [validatePromotionCta] stays BuildContext-free and unit-testable.
enum PromotionCtaError { incomplete, unavailableVendor }

/// The button only shows when both a label and a store are set, so they're
/// required together (or both left empty). A linked store must be an
/// approved vendor (the customer carousel can only open a store it can
/// show): [vendor] is that store as just read from the server — null when
/// it doesn't exist or couldn't be read, so an unverified id is rejected
/// rather than trusted. The CTA contract itself is unchanged: `ctaAction`
/// stores the chosen vendor's id (see [Promotion.ctaAction] and
/// PromoBannerCarousel).
PromotionCtaError? validatePromotionCta({
  required String? label,
  required String? vendorId,
  required Vendor? vendor,
}) {
  final hasLabel = label != null && label.trim().isNotEmpty;
  if (vendorId == null) return hasLabel ? PromotionCtaError.incomplete : null;
  if (vendor == null || vendor.id != vendorId || vendor.approvalStatus != ApprovalStatus.approved) {
    return PromotionCtaError.unavailableVendor;
  }
  return hasLabel ? null : PromotionCtaError.incomplete;
}

/// Admin CRUD screen for `promotions/{promotionId}` — the content behind
/// the customer Home screen's [PromoBannerCarousel]. Mirrors
/// MenuManagementScreen's list + bottom-sheet-form + two-phase
/// (create-doc, upload-media, update-doc) save pattern rather than
/// inventing a new admin UI shape. Not paginated: promotions are a small,
/// admin-curated set (the carousel's content), streamed live.
class AdminPromotionsScreen extends ConsumerStatefulWidget {
  const AdminPromotionsScreen({super.key});

  @override
  ConsumerState<AdminPromotionsScreen> createState() => _AdminPromotionsScreenState();
}

class _AdminPromotionsScreenState extends ConsumerState<AdminPromotionsScreen> {
  // Promotions with a delete in flight — their actions are disabled until
  // it settles, so the delete can't be sent twice.
  final Set<String> _deleting = {};

  Future<void> _openForm({Promotion? existing}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: _PromotionForm(existing: existing),
      ),
    );
  }

  Future<void> _confirmDelete(Promotion promotion) async {
    if (_deleting.contains(promotion.id)) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showConfirmDialog(
      context,
      message: l10n.deletePromotionConfirmMessage,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    HapticFeedback.lightImpact();
    setState(() => _deleting.add(promotion.id));
    await runAdminWrite(
      context,
      () => ref.read(firestoreServiceProvider).deletePromotion(promotion.id),
      successMessage: l10n.promotionDeletedMessage,
    );
    if (mounted) setState(() => _deleting.remove(promotion.id));
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => _openForm(),
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
                      busy: _deleting.contains(promotion.id),
                      onEdit: () => _openForm(existing: promotion),
                      onDelete: () => _confirmDelete(promotion),
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
    required this.busy,
    required this.onEdit,
    required this.onDelete,
    required this.onSetEnabled,
    super.key,
  });

  final Promotion promotion;
  // A delete is in flight: the actions menu is replaced by a spinner.
  final bool busy;
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
                if (busy)
                  SizedBox.square(
                    key: ValueKey('admin_promotion_busy_${promotion.id}'),
                    dimension: AppSizes.minTapTarget,
                    child: Center(child: buttonSpinner(colorScheme.primary, size: AppSizes.iconMedium)),
                  )
                else
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
  late final FirestoreService _firestore;
  late final TextEditingController _titleController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _ctaLabelController;
  late final TextEditingController _orderController;
  late bool _enabled;
  late PromotionMediaType _mediaType;
  String? _ctaVendorId;
  // The linked store as last read from the server (see validatePromotionCta).
  Vendor? _ctaVendor;
  bool _ctaVendorLoading = false;
  File? _pickedMedia;
  // Id of the doc a previous, partly failed save of a NEW promotion already
  // created — a retry finishes that doc instead of creating a second one,
  // and closing the form without finishing deletes it (see dispose).
  String? _createdId;
  bool _saved = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _firestore = ref.read(firestoreServiceProvider);
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _ctaLabelController = TextEditingController(text: existing?.ctaLabel ?? '');
    _orderController = TextEditingController(text: (existing?.order ?? 0).toString());
    _enabled = existing?.enabled ?? true;
    _mediaType = existing?.mediaType ?? PromotionMediaType.image;
    final ctaAction = existing?.ctaAction?.trim();
    _ctaVendorId = (ctaAction == null || ctaAction.isEmpty) ? null : ctaAction;
    if (_ctaVendorId != null) {
      _ctaVendorLoading = true;
      _loadCtaVendor();
    }
  }

  @override
  void dispose() {
    // A new promotion whose save failed part-way and was then abandoned:
    // remove its disabled placeholder doc rather than leave an empty
    // promotion behind. Best effort — a failure here changes nothing a
    // customer sees (the placeholder is disabled).
    final abandoned = _createdId;
    if (abandoned != null && !_saved) {
      unawaited(_firestore.deletePromotion(abandoned).then<void>((_) {}, onError: (Object _) {}));
    }
    _titleController.dispose();
    _descriptionController.dispose();
    _ctaLabelController.dispose();
    _orderController.dispose();
    super.dispose();
  }

  // Reads the stored linked store once, for its name and approval state
  // (called from initState with _ctaVendorLoading already set).
  Future<void> _loadCtaVendor() async {
    final vendorId = _ctaVendorId;
    if (vendorId == null) return;
    Vendor? vendor;
    try {
      vendor = await _firestore.fetchVendor(vendorId);
    } catch (_) {
      vendor = null; // shown as an unavailable store; saving re-checks
    }
    if (!mounted || _ctaVendorId != vendorId) return;
    setState(() {
      _ctaVendor = vendor;
      _ctaVendorLoading = false;
    });
  }

  Future<void> _pickCtaVendor() async {
    final picked = await showModalBottomSheet<({Vendor? vendor})>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const _CtaVendorPickerSheet(),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _ctaVendor = picked.vendor;
      _ctaVendorId = picked.vendor?.id;
      _ctaVendorLoading = false;
    });
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
  //
  // Editing writes only the form's fields, and leaves `enabled` alone
  // unless the admin changed it here — so toggling a promotion in the list
  // while its form is open isn't undone by saving the form.
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context)!;
    if (widget.existing == null && _pickedMedia == null) {
      setState(() => _errorMessage = l10n.selectMediaRequiredError);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    try {
      // Re-read the linked store: it may have been rejected since it was
      // picked. The validator then reports it before anything is written.
      final vendorId = _ctaVendorId;
      if (vendorId != null) {
        final fresh = await _firestore.fetchVendor(vendorId);
        if (!mounted) return;
        setState(() => _ctaVendor = fresh);
        if (!_formKey.currentState!.validate()) return;
      }

      final title = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      final ctaLabel = _ctaLabelController.text.trim().isEmpty ? null : _ctaLabelController.text.trim();
      final order = int.parse(_orderController.text.trim());
      final existing = widget.existing;

      final promotionId = existing?.id ??
          _createdId ??
          await _firestore.addPromotion(
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
      if (existing == null) _createdId = promotionId;

      var mediaUrl = existing?.mediaUrl ?? '';
      if (_pickedMedia != null) {
        final fileName = _mediaType == PromotionMediaType.image ? 'media.jpg' : 'media.mp4';
        mediaUrl = await ref.read(storageServiceProvider).uploadPromotionMedia(promotionId, _pickedMedia!, fileName);
      }

      await _firestore.updatePromotionDetails(
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
        includeEnabled: existing == null || _enabled != existing.enabled,
      );
      _saved = true;
      messenger.showSnackBar(buildAppSnackBar(colorScheme, l10n.promotionSavedMessage));
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String? _validateCta(AppLocalizations l10n) {
    return switch (validatePromotionCta(label: _ctaLabelController.text, vendorId: _ctaVendorId, vendor: _ctaVendor)) {
      null => null,
      PromotionCtaError.incomplete => l10n.ctaIncompleteError,
      PromotionCtaError.unavailableVendor => l10n.ctaVendorUnavailableError,
    };
  }

  String _ctaVendorLabel(AppLocalizations l10n) {
    final vendorId = _ctaVendorId;
    if (vendorId == null) return l10n.ctaNoVendorOption;
    if (_ctaVendorLoading) return l10n.loadingLabel;
    final vendor = _ctaVendor;
    // A stored store that's gone keeps showing (never silently dropped);
    // the validator asks for a valid one.
    return vendor != null && vendor.id == vendorId ? vendor.name : l10n.unknownVendorOption;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

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
            // The linked store is picked from a searchable, paged list of
            // approved stores (never a dropdown of every vendor).
            FormField<String?>(
              key: const ValueKey('admin_promotion_cta_vendor'),
              validator: (_) => _validateCta(l10n),
              builder: (field) => Semantics(
                button: true,
                label: l10n.ctaChooseVendorButton,
                child: InkWell(
                  borderRadius: AppRadius.small,
                  onTap: _isSubmitting ? null : _pickCtaVendor,
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.ctaActionFieldLabel,
                      errorText: field.errorText,
                      errorMaxLines: 3,
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(_ctaVendorLabel(l10n), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
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
              // Wait for the linked store's details, so it can be checked.
              onPressed: _isSubmitting || _ctaVendorLoading ? null : _save,
              child: _isSubmitting ? buttonSpinner(Theme.of(context).colorScheme.onPrimary) : Text(l10n.saveButton),
            ),
          ],
        ),
      ),
    );
  }
}

/// Picks the store a promotion's CTA opens: "No linked store", or one of
/// the approved stores — 25 per page with "Load more", searchable by a
/// server-side name prefix. Pops `(vendor: …)` (null vendor = none), or
/// nothing when dismissed.
class _CtaVendorPickerSheet extends ConsumerStatefulWidget {
  const _CtaVendorPickerSheet();

  @override
  ConsumerState<_CtaVendorPickerSheet> createState() => _CtaVendorPickerSheetState();
}

class _CtaVendorPickerSheetState extends ConsumerState<_CtaVendorPickerSheet> {
  String _query = '';

  late final PagedListController<Vendor> _vendors = PagedListController(
    idOf: (vendor) => vendor.id,
    fetchPage: (cursor) => ref
        .read(firestoreServiceProvider)
        .fetchVendorsPage(status: ApprovalStatus.approved, namePrefix: _query, after: cursor),
  );

  @override
  void initState() {
    super.initState();
    _vendors.refresh();
  }

  @override
  void dispose() {
    _vendors.dispose();
    super.dispose();
  }

  void _setQuery(String query) {
    if (query == _query) return;
    setState(() => _query = query);
    _vendors.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.ctaActionFieldLabel, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AppSpacing.md),
                AdminSearchField(
                  hintText: l10n.searchVendorsHint,
                  helperText: l10n.searchStartsWithHelper,
                  onChanged: _setQuery,
                ),
                ListTile(
                  key: const ValueKey('admin_cta_vendor_none'),
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.link_off),
                  title: Text(l10n.ctaNoVendorOption),
                  onTap: () => Navigator.of(context).pop((vendor: null)),
                ),
                const Divider(height: 1),
                Expanded(
                  child: AdminPagedList<Vendor>(
                    controller: _vendors,
                    emptyMessage: l10n.noVendorsFoundMessage,
                    itemBuilder: (context, vendor, index) => ListTile(
                      key: ValueKey('admin_cta_vendor_${vendor.id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.storefront_outlined),
                      title: Text(vendor.name, maxLines: 2, overflow: TextOverflow.ellipsis),
                      onTap: () => Navigator.of(context).pop((vendor: vendor)),
                    ),
                  ),
                ),
              ],
            ),
          ),
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
