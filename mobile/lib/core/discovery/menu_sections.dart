import '../../models/vendor.dart';

/// One tab/section of VendorMenuScreen's sticky-tabbed menu — see
/// `features/customer/widgets/store_sticky_tabs.dart`.
class MenuSection {
  const MenuSection({required this.title, required this.items, this.isMostOrdered = false});

  final String title;
  final List<MenuItem> items;

  /// True only for the single synthetic "most ordered" section `buildMenuSections`
  /// prepends — lets callers pick a different layout (a horizontal carousel)
  /// for it without string-comparing `title` against the localized label.
  final bool isMostOrdered;
}

/// Items with the highest real, server-aggregated `orderCount` first — same
/// "doesn't qualify at all if zero" rule as `popularVendors` in
/// `vendor_carousels.dart`. Never a fabricated ranking.
List<MenuItem> mostOrderedItems(List<MenuItem> items, {int limit = 5}) {
  final ordered = items.where((item) => item.orderCount > 0).toList()
    ..sort((a, b) => b.orderCount.compareTo(a.orderCount));
  return ordered.take(limit).toList();
}

/// Groups [items] into the sections VendorMenuScreen renders: "Most ordered"
/// first (when non-empty), then one section per distinct vendor-authored
/// `MenuItem.section` value in first-seen order (matching how the vendor
/// built their own menu), with unsectioned items grouped under
/// [defaultSectionTitle]. Title strings are passed in rather than resolved
/// here so this stays a pure function with no l10n/BuildContext dependency.
List<MenuSection> buildMenuSections(
  List<MenuItem> items, {
  required String mostOrderedTitle,
  required String defaultSectionTitle,
  int mostOrderedLimit = 5,
}) {
  final sections = <MenuSection>[];

  final mostOrdered = mostOrderedItems(items, limit: mostOrderedLimit);
  if (mostOrdered.isNotEmpty) {
    sections.add(MenuSection(title: mostOrderedTitle, items: mostOrdered, isMostOrdered: true));
  }

  final grouped = <String, List<MenuItem>>{};
  for (final item in items) {
    final section = item.section?.trim();
    final key = (section == null || section.isEmpty) ? defaultSectionTitle : section;
    grouped.putIfAbsent(key, () => []).add(item);
  }
  for (final entry in grouped.entries) {
    sections.add(MenuSection(title: entry.key, items: entry.value));
  }

  return sections;
}
