import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Fade + slide entrance for list rows, staggered by [index] so items reveal
/// in sequence instead of popping in all at once. The per-item delay is
/// capped so long lists don't take forever to finish revealing.
extension StaggeredListItem on Widget {
  Widget staggeredEntrance(int index) {
    final delay = Duration(milliseconds: (index * 40).clamp(0, 400));
    return animate()
        .fadeIn(duration: 300.ms, delay: delay)
        .slideY(begin: 0.08, end: 0, duration: 300.ms, delay: delay, curve: Curves.easeOut);
  }
}
