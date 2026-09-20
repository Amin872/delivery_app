import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

import '../../../core/discovery/menu_sections.dart';

const double storeStickyTabsHeight = 48;

/// Pinned tab bar for VendorMenuScreen's menu — one tab per `MenuSection`.
/// Purely presentational, like `StickyCategoryBarDelegate`: [selectedIndex]/
/// [onTap] are owned by the screen, which also runs the scroll-position
/// tracking that keeps [selectedIndex] in sync as the user scrolls (a
/// `SliverPersistentHeaderDelegate` has no scroll-offset access of its own
/// beyond its own extent).
class StoreStickyTabsDelegate extends SliverPersistentHeaderDelegate {
  StoreStickyTabsDelegate({
    required this.sections,
    required this.selectedIndex,
    required this.onTap,
  });

  final List<MenuSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  double get minExtent => storeStickyTabsHeight;

  @override
  double get maxExtent => storeStickyTabsHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return ColoredBox(
      // Opaque — pinned above the scrolling menu, needs its own background.
      color: Theme.of(context).colorScheme.surface,
      child: _StickyTabsRow(sections: sections, selectedIndex: selectedIndex, onTap: onTap),
    );
  }

  @override
  bool shouldRebuild(covariant StoreStickyTabsDelegate oldDelegate) =>
      oldDelegate.selectedIndex != selectedIndex || oldDelegate.sections != sections;
}

/// The tab row's actual content and behavior, split out of the delegate into
/// a real `State` so it can own a `ScrollController` and keep the active tab
/// scrolled into view — a `SliverPersistentHeaderDelegate` is rebuilt fresh
/// on every scroll-spy update, so that state can't live directly on it.
class _StickyTabsRow extends StatefulWidget {
  const _StickyTabsRow({required this.sections, required this.selectedIndex, required this.onTap});

  final List<MenuSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onTap;

  @override
  State<_StickyTabsRow> createState() => _StickyTabsRowState();
}

class _StickyTabsRowState extends State<_StickyTabsRow> {
  final _scrollController = ScrollController();
  final List<GlobalKey> _tabKeys = [];

  void _syncTabKeys() {
    while (_tabKeys.length < widget.sections.length) {
      _tabKeys.add(GlobalKey());
    }
    if (_tabKeys.length > widget.sections.length) {
      _tabKeys.removeRange(widget.sections.length, _tabKeys.length);
    }
  }

  // Keeps the active tab in view both when the user taps a different tab and
  // when vertical scrolling changes it (see VendorMenuScreen's scroll-spy) —
  // satisfies "the category bar should automatically scroll horizontally so
  // the active category is visible" in both directions.
  //
  // Deliberately NOT `Scrollable.ensureVisible(tabContext, ...)`: this tab
  // row is itself nested inside VendorMenuScreen's outer vertical
  // CustomScrollView (it's the content of a pinned SliverPersistentHeader),
  // and `Scrollable.ensureVisible` walks *every* ancestor Scrollable it
  // finds, not just the nearest one — confirmed live, it was also dragging
  // the whole page back up to the top every time the active tab changed.
  // Resolving the reveal offset against just this row's own viewport and
  // driving `_scrollController` directly keeps the correction scoped to the
  // horizontal tab bar only.
  void _scrollActiveTabIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.selectedIndex >= _tabKeys.length || !_scrollController.hasClients) {
        return;
      }
      final renderObject = _tabKeys[widget.selectedIndex].currentContext?.findRenderObject();
      if (renderObject == null) return;
      final viewport = RenderAbstractViewport.of(renderObject);
      final target = viewport
          .getOffsetToReveal(renderObject, 0.5)
          .offset
          .clamp(_scrollController.position.minScrollExtent, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  void initState() {
    super.initState();
    _syncTabKeys();
  }

  @override
  void didUpdateWidget(covariant _StickyTabsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTabKeys();
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollActiveTabIntoView();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListView.builder(
      controller: _scrollController,
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: widget.sections.length,
      itemBuilder: (context, index) {
        final selected = index == widget.selectedIndex;
        return Padding(
          key: _tabKeys[index],
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => widget.onTap(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                // primaryContainer, not primary — Material 3's dark
                // ColorScheme.primary is a pale accent tone, wrong for a
                // solid tab fill (see AppGradients.primary's doc comment
                // in app_theme.dart for the full reasoning).
                color: selected ? colorScheme.primaryContainer : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.sections[index].title,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: selected ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
