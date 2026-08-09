import 'package:flutter/material.dart';

/// Fade+slide transition shared by every route in the app — both go_router
/// pages (via `app_router.dart`'s `_fadeSlidePage`) and plain
/// `Navigator.push` (via [fadeSlideRoute] below) — so navigation feels
/// consistent everywhere instead of only on individually-styled screens.
const fadeSlideTransitionDuration = Duration(milliseconds: 250);

Widget buildFadeSlideTransition(
  BuildContext context,
  Animation<double> animation,
  Animation<double> secondaryAnimation,
  Widget child,
) {
  final curved = CurvedAnimation(parent: animation, curve: Curves.easeOut);
  return FadeTransition(
    opacity: curved,
    child: SlideTransition(
      position: Tween<Offset>(begin: const Offset(0, 0.03), end: Offset.zero).animate(curved),
      child: child,
    ),
  );
}

/// `Navigator.push`/`pushReplacement`-compatible route using the same
/// transition as go_router's `_fadeSlidePage`.
Route<T> fadeSlideRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: fadeSlideTransitionDuration,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: buildFadeSlideTransition,
  );
}
