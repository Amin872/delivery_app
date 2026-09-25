import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/promotion.dart';
import '../../customer/screens/customer_home_screen.dart' show firestoreServiceProvider;
import '../../vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import '../widgets/admin_scaffold.dart';

final allPromotionsProvider = StreamProvider<List<Promotion>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllPromotions();
});

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
    if (confirmed == true) {
      HapticFeedback.lightImpact();
      await ref.read(firestoreServiceProvider).deletePromotion(promotion.id);
    }
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
                  return Center(child: Text(l10n.noPromotionsMessage));
                }
                return ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: promotions.length,
                  itemBuilder: (context, index) {
                    final promotion = promotions[index];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundImage: promotion.mediaType == PromotionMediaType.image
                              ? NetworkImage(promotion.mediaUrl)
                              : null,
                          child: promotion.mediaType == PromotionMediaType.video
                              ? const Icon(Icons.videocam_outlined)
                              : null,
                        ),
                        title: Text(
                          promotion.title?.isNotEmpty == true ? promotion.title! : l10n.promotionTitleFieldLabel,
                          style: promotion.enabled ? null : TextStyle(color: Theme.of(context).disabledColor),
                        ),
                        subtitle: Text('#${promotion.order}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: promotion.enabled,
                              onChanged: (value) {
                                HapticFeedback.selectionClick();
                                ref.read(firestoreServiceProvider).setPromotionEnabled(promotion.id, value);
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: l10n.editTooltip,
                              onPressed: () => _openForm(context, existing: promotion),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: l10n.deleteTooltip,
                              onPressed: () => _confirmDelete(context, ref, promotion),
                            ),
                          ],
                        ),
                      ),
                    ).staggeredEntrance(index);
                  },
                );
              },
              loading: () => const ListSkeletonLoader(),
              error: (error, _) => Center(child: Text(localizedErrorMessage(context, error))),
            ),
          ),
        ],
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
  late final TextEditingController _ctaActionController;
  late final TextEditingController _orderController;
  late bool _enabled;
  late PromotionMediaType _mediaType;
  File? _pickedMedia;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _titleController = TextEditingController(text: existing?.title ?? '');
    _descriptionController = TextEditingController(text: existing?.description ?? '');
    _ctaLabelController = TextEditingController(text: existing?.ctaLabel ?? '');
    _ctaActionController = TextEditingController(text: existing?.ctaAction ?? '');
    _orderController = TextEditingController(text: (existing?.order ?? 0).toString());
    _enabled = existing?.enabled ?? true;
    _mediaType = existing?.mediaType ?? PromotionMediaType.image;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _ctaLabelController.dispose();
    _ctaActionController.dispose();
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
  // mediaUrl) first, then upload, then write the real mediaUrl.
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
    try {
      final firestore = ref.read(firestoreServiceProvider);
      final title = _titleController.text.trim().isEmpty ? null : _titleController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      final ctaLabel = _ctaLabelController.text.trim().isEmpty ? null : _ctaLabelController.text.trim();
      final ctaAction = _ctaActionController.text.trim().isEmpty ? null : _ctaActionController.text.trim();
      final order = int.parse(_orderController.text.trim());
      final isNew = widget.existing == null;

      final promotionId = isNew
          ? await firestore.addPromotion(
              Promotion(
                id: '',
                title: title,
                description: description,
                mediaUrl: '',
                mediaType: _mediaType,
                ctaLabel: ctaLabel,
                ctaAction: ctaAction,
                order: order,
                enabled: _enabled,
              ),
            )
          : widget.existing!.id;

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
          ctaAction: ctaAction,
          order: order,
          enabled: _enabled,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _errorMessage = localizedErrorMessage(context, error));
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
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.existing == null ? l10n.addPromotionTitle : l10n.editPromotionTitle,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
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
              const SizedBox(height: 12),
              _MediaPickerPreview(
                mediaType: _mediaType,
                networkUrl: widget.existing?.mediaUrl,
                localFile: _pickedMedia,
                onTap: _pickMedia,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleController,
                decoration: InputDecoration(labelText: l10n.promotionTitleFieldLabel),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(labelText: l10n.promotionDescriptionFieldLabel),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ctaLabelController,
                decoration: InputDecoration(labelText: l10n.ctaLabelFieldLabel),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _ctaActionController,
                decoration: InputDecoration(labelText: l10n.ctaActionFieldLabel),
              ),
              const SizedBox(height: 12),
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
              const SizedBox(height: 12),
              if (_errorMessage != null)
                Text(_errorMessage!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              GradientButton(
                onPressed: _isSubmitting ? null : _save,
                child: _isSubmitting ? buttonSpinner(Theme.of(context).colorScheme.onPrimary) : Text(l10n.saveButton),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tap-to-pick preview for the form's media field — same
/// preview-local-file-else-network-else-placeholder logic as
/// ImagePickerAvatar, just rectangular (not a circular avatar) and able to
/// represent a picked/saved video (no thumbnail decoding, just an icon)
/// alongside an image preview.
class _MediaPickerPreview extends StatelessWidget {
  const _MediaPickerPreview({required this.mediaType, required this.onTap, this.networkUrl, this.localFile});

  final PromotionMediaType mediaType;
  final VoidCallback onTap;
  final String? networkUrl;
  final File? localFile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final hasLocalFile = localFile != null;
    final hasNetworkImage = !hasLocalFile && mediaType == PromotionMediaType.image && (networkUrl?.isNotEmpty ?? false);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          image: hasLocalFile && mediaType == PromotionMediaType.image
              ? DecorationImage(image: FileImage(localFile!), fit: BoxFit.cover)
              : hasNetworkImage
              ? DecorationImage(image: NetworkImage(networkUrl!), fit: BoxFit.cover)
              : null,
        ),
        child: (hasLocalFile && mediaType == PromotionMediaType.image) || hasNetworkImage
            ? null
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      hasLocalFile
                          ? Icons.videocam_outlined
                          : (mediaType == PromotionMediaType.image
                                ? Icons.add_photo_alternate_outlined
                                : Icons.video_call_outlined),
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      hasLocalFile ? (localFile!.uri.pathSegments.last) : l10n.selectMediaLabel,
                      style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
