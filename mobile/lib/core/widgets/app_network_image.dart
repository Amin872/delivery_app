import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Disk-cached, fade-in network image with a shimmering placeholder and a
/// graceful error state — the single place `Image.network` should be
/// replaced across the app so every product/vendor photo gets caching,
/// a loading state, and broken-URL handling for free instead of each
/// screen reinventing it.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    // Rendered at the widget's own pixel size by default (no upscaling
    // beyond what's asked for) — callers displaying many small thumbnails
    // (e.g. a dense grid) can pass explicit, smaller values to cap decoded
    // bitmap size and cut memory use, per cached_network_image's own
    // recommended usage.
    this.memCacheWidth,
    this.memCacheHeight,
    this.alignment = Alignment.center,
    super.key,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? memCacheWidth;
  final int? memCacheHeight;
  // Lets a caller bias which part of a cropped (BoxFit.cover) photo stays
  // visible — e.g. the vendor hero, which wants the subject kept slightly
  // above center rather than whatever the true image center happens to be.
  // `Alignment` (not the RTL-aware `AlignmentDirectional`/`AlignmentGeometry`)
  // because that's what `CachedNetworkImage`/`Image` themselves require, and
  // vertical-only bias is direction-agnostic anyway.
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      memCacheWidth: memCacheWidth,
      memCacheHeight: memCacheHeight,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Shimmer.fromColors(
        baseColor: colorScheme.surfaceContainerHighest,
        highlightColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: Container(width: width, height: height, color: colorScheme.surfaceContainerHighest),
      ),
      errorWidget: (context, url, error) => Container(
        width: width,
        height: height,
        color: colorScheme.surfaceContainerHighest,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: colorScheme.onSurfaceVariant,
          size: (width != null && width! < 48) ? width! * 0.5 : 32,
        ),
      ),
    );

    if (borderRadius == null) return image;
    return ClipRRect(borderRadius: borderRadius!, child: image);
  }
}
