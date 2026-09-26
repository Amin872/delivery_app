import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_network_image.dart';

/// Sharp hero photo behind VendorMenuScreen's SliverAppBar `flexibleSpace`,
/// clipped to a smooth curved bottom edge (see [_HeroCurveClipper]) so it
/// reads as a deliberate shaped panel rather than a plain rectangle, with a
/// subtle top scrim so the back/favorite buttons and search pill stay
/// legible over any photo — kept as its own widget since the treatment is a
/// distinct visual unit, reused nowhere else but self-contained enough to
/// reason about independently of the app bar.
///
/// The curve's "flows into the dark background" feel isn't painted here at
/// all: [_HeroCurveClipper] just cuts the corners away, and
/// `SliverAppBar.backgroundColor` (set to [VendorPalette.background] by the
/// caller) shows through underneath via normal compositing — one color
/// value has to match, not a second gradient layer trying to fake it.
///
/// Uses [AppNetworkImage] (this screen's only prior `Image.network` call,
/// per Phase 2) so the hero photo gets disk caching, a loading placeholder,
/// and error handling instead of refetching un-cached on every rebuild.
class StoreHeroBackground extends StatelessWidget {
  const StoreHeroBackground({required this.imageUrl, super.key});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    return ClipPath(
      clipper: const _HeroCurveClipper(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          imageUrl != null
              ? AppNetworkImage(
                  imageUrl: imageUrl!,
                  fit: BoxFit.cover,
                  // Biased slightly above true center: food/storefront
                  // photos usually put the interesting subject in the
                  // upper-middle frame, and the lower edge is already
                  // heading into the curved cutaway below, so it can afford
                  // to lose a little more than the top does on a tall
                  // source photo.
                  alignment: const Alignment(0, -0.2),
                )
              : const ColoredBox(color: VendorPalette.surface),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppPalette.imageScrim, // button-contrast scrim
                  Colors.transparent,
                ],
                stops: [0.0, 0.35],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Cuts a smooth, symmetric ∪ curve into the bottom edge of the hero: both
/// bottom corners stay at the hero's full height and the middle sweeps
/// *up* via a single quadratic Bézier — i.e. the two sides read taller than
/// the center, not the other way around. A plain `BorderRadius` genuinely
/// can't produce this (that can only round corners, never lift the center
/// above them), which is the actual justification for a `CustomClipper`
/// here rather than a cheaper `ClipRRect`. Resolves entirely off the
/// incoming `size`, so it scales cleanly at any hero width instead of a
/// fixed-pixel curve.
class _HeroCurveClipper extends CustomClipper<Path> {
  const _HeroCurveClipper();

  // How far the curve rises above the hero's full height at its shallowest
  // (center) point. Fixed rather than proportional to `size.height`: the
  // curve should read the same regardless of how tall the hero itself
  // happens to be on a given device.
  static const _curveDepth = 40.0;

  @override
  Path getClip(Size size) {
    final path = Path()
      ..lineTo(0, size.height)
      ..quadraticBezierTo(
        size.width / 2,
        size.height - _curveDepth * 2,
        size.width,
        size.height,
      )
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
