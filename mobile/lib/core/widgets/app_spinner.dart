import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

/// Compact spinner for a submitting button — replaces the plain
/// `CircularProgressIndicator` every form's submit button used to swap its
/// label for while awaiting a response.
Widget buttonSpinner(Color color, {double size = 20}) {
  return SpinKitThreeBounce(color: color, size: size);
}

/// Full-screen loading state — used where there's no list shape to skeleton
/// (e.g. the role-gate while resolving which home screen to show).
Widget screenSpinner(BuildContext context, {double size = 48}) {
  return SpinKitFadingCircle(color: Theme.of(context).colorScheme.primary, size: size);
}
