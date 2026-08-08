import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Tappable circular image preview that opens the gallery picker on tap.
/// Shows [localFile] if set (a pick made this session, not yet uploaded),
/// falling back to [networkUrl] (the currently-saved image), falling back
/// to a placeholder camera icon. Upload itself is the caller's job — this
/// widget only gets a [File] into [onPicked].
class ImagePickerAvatar extends StatelessWidget {
  const ImagePickerAvatar({
    required this.onPicked,
    this.networkUrl,
    this.localFile,
    this.radius = 40,
    super.key,
  });

  final ValueChanged<File> onPicked;
  final String? networkUrl;
  final File? localFile;
  final double radius;

  Future<void> _pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null) onPicked(File(picked.path));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ImageProvider? image =
        localFile != null ? FileImage(localFile!) : (networkUrl != null ? NetworkImage(networkUrl!) : null);

    return GestureDetector(
      onTap: _pick,
      child: CircleAvatar(
        radius: radius,
        backgroundColor: colorScheme.surfaceContainerHighest,
        backgroundImage: image,
        child: image == null
            ? Icon(Icons.add_a_photo_outlined, color: colorScheme.onSurfaceVariant)
            : null,
      ),
    );
  }
}
