import '../../models/vendor.dart';

/// Pure filter/sort functions powering CustomerHomeScreen's dynamic list of
/// carousel sections (see `features/customer/widgets/product_carousel.dart`).
/// Kept free of Firebase/Riverpod, mirroring `core/stats/menu_item_tally.dart`,
/// so each rule is trivially unit-testable on its own. None of these
/// fabricate data — a vendor simply doesn't qualify for a section if the
/// real field it depends on (`etaMinMinutes`, `deliveryFee`, `ratingCount`)
/// isn't set.
///
/// The home feed is product-first (see the redesign plan): these functions
/// still select *vendors* — that's the real, tested criterion for each
/// section ("fastest," "free delivery," ...) — but [productsFromVendors]
/// is the final step that turns a qualifying vendor list into the menu
/// items a carousel actually renders.

/// Vendors with the shortest quoted ETA first. A vendor with no ETA set
/// sorts after every vendor that has one — never fabricated, never assumed
/// to be "fast" by default.
List<Vendor> fastestDeliveryVendors(List<Vendor> vendors, {int limit = 5}) {
  final sorted = [...vendors]..sort((a, b) {
      final aEta = a.etaMinMinutes;
      final bEta = b.etaMinMinutes;
      if (aEta == null && bEta == null) return 0;
      if (aEta == null) return 1;
      if (bEta == null) return -1;
      return aEta.compareTo(bEta);
    });
  return sorted.take(limit).toList();
}

/// Vendors offering free delivery — the app's only real "deal" signal today
/// (see the redesign plan's Context: no discount/promotion field exists).
List<Vendor> dealVendors(List<Vendor> vendors) {
  return vendors.where((v) => v.deliveryFee == 0).toList();
}

/// The "Selfcare" section's source vendors — pharmacy/health & beauty
/// storefronts.
List<Vendor> selfcareVendors(List<Vendor> vendors) {
  return vendors.where((v) => v.category == VendorCategory.pharmacy).toList();
}

/// Vendors with the most reviews first — a real engagement signal already
/// aggregated onto `Vendor` by the onReviewCreated Cloud Function (see
/// CLAUDE.md's ratings architecture note). Vendors with zero reviews don't
/// qualify at all, rather than being sorted-but-shown last.
List<Vendor> popularVendors(List<Vendor> vendors, {int limit = 5}) {
  final rated = vendors.where((v) => v.ratingCount > 0).toList()
    ..sort((a, b) => b.ratingCount.compareTo(a.ratingCount));
  return rated.take(limit).toList();
}

/// Plain category equality filter, powering one section per remaining
/// `VendorCategory` (pharmacy is covered by [selfcareVendors] instead, so
/// callers should skip it here to avoid a duplicate section).
List<Vendor> vendorsInCategory(List<Vendor> vendors, VendorCategory category) {
  return vendors.where((v) => v.category == category).toList();
}

/// Flattens a qualifying vendor list (from one of the functions above) into
/// the available menu items a `ProductCarousel` renders — the product-first
/// feed's items are always sourced from a vendor-level rule, never picked
/// directly, so "why is this product here" always traces back to a real
/// vendor-level signal (fastest, free delivery, category, ...).
List<MenuItem> productsFromVendors(
  List<MenuItem> allItems,
  List<Vendor> vendors, {
  int limit = 10,
}) {
  final vendorIds = vendors.map((v) => v.id).toSet();
  return allItems
      .where((item) => item.available && vendorIds.contains(item.vendorId))
      .take(limit)
      .toList();
}
