import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radius.dart';
import '../../../core/theme/app_sizes.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_snackbar.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../l10n/app_localizations.dart';

/// Picks one proof-of-delivery photo from [source]; null when the driver
/// backs out. Mobile only: the proof pipeline (StorageService.
/// uploadOrderProof) takes a dart:io [File].
typedef ProofPhotoPicker = Future<File?> Function(ImageSource source);

/// The real picker; tests override it.
final proofPhotoPickerProvider = Provider<ProofPhotoPicker>((ref) => (source) async {
      final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
      return picked == null ? null : File(picked.path);
    });

/// Why a pick failed, from image_picker's platform error codes
/// (camera_access_denied, photo_access_denied, no_available_camera, …).
enum ProofPickFailure { permissionDenied, cameraUnavailable, other }

ProofPickFailure proofPickFailure(Object error) {
  final code = error is PlatformException ? error.code.toLowerCase() : '';
  if (code.contains('denied') || code.contains('permission')) return ProofPickFailure.permissionDenied;
  if (code.contains('camera')) return ProofPickFailure.cameraUnavailable;
  return ProofPickFailure.other;
}

/// The driver's proof-of-delivery step: a preview of the chosen photo (or
/// a placeholder) and two explicit sources — take a photo or choose one
/// from the gallery. Picking again replaces the photo. A failed pick shows
/// a localized message, never the raw platform error.
class DriverProofPicker extends ConsumerStatefulWidget {
  const DriverProofPicker({required this.file, required this.onPicked, super.key});

  final File? file;
  final ValueChanged<File> onPicked;

  @override
  ConsumerState<DriverProofPicker> createState() => _DriverProofPickerState();
}

class _DriverProofPickerState extends ConsumerState<DriverProofPicker> {
  bool _picking = false;

  Future<void> _pick(ImageSource source) async {
    if (_picking) return;
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    setState(() => _picking = true);
    try {
      final file = await ref.read(proofPhotoPickerProvider)(source);
      if (file != null) widget.onPicked(file);
    } catch (error) {
      final message = switch (proofPickFailure(error)) {
        ProofPickFailure.permissionDenied => l10n.proofPermissionDeniedMessage,
        ProofPickFailure.cameraUnavailable => l10n.proofCameraUnavailableMessage,
        ProofPickFailure.other => l10n.proofPickFailedMessage,
      };
      messenger.showSnackBar(buildAppSnackBar(colorScheme, message, isError: true));
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final file = widget.file;
    const previewSize = AppSizes.largeButtonHeight;

    final placeholder = Icon(Icons.add_a_photo_outlined, color: AppColors.textMuted(colorScheme));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Its own semantics node, so a screen reader announces whether a
            // photo is attached rather than merging it into nearby text.
            Semantics(
              key: const ValueKey('driver_proof_preview'),
              container: true,
              image: file != null,
              label: file != null ? l10n.proofPhotoAttachedLabel : l10n.proofNoPhotoLabel,
              child: ClipRRect(
                borderRadius: AppRadius.medium,
                child: Container(
                  width: previewSize,
                  height: previewSize,
                  color: colorScheme.surfaceContainerHighest,
                  alignment: Alignment.center,
                  child: _picking
                      ? buttonSpinner(colorScheme.primary, size: AppSizes.iconMedium)
                      : file == null
                          ? placeholder
                          : Image.file(
                              file,
                              width: previewSize,
                              height: previewSize,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, __, ___) => placeholder,
                            ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(l10n.proofOfDeliveryHint, style: textTheme.bodyMedium)),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('driver_proof_camera'),
              onPressed: _picking ? null : () => _pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(l10n.proofTakePhotoButton),
            ),
            OutlinedButton.icon(
              key: const ValueKey('driver_proof_gallery'),
              onPressed: _picking ? null : () => _pick(ImageSource.gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.proofChooseFromGalleryButton),
            ),
          ],
        ),
      ],
    );
  }
}
