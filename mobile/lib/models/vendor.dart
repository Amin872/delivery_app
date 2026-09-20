import '../core/parsing/safe_enum.dart';

enum VendorApprovalStatus { pending, approved, rejected }

enum VendorCategory { groceries, restaurants, bakery, drinks, pharmacy }

class Vendor {
  final String id;
  final String ownerId;
  final String name;
  final String description;
  // Wide hero/cover photo shown behind the storefront header — NOT the
  // vendor's logo. Kept separate from [logoUrl] below: a storefront photo
  // and a square logo mark are different assets with different aspect
  // ratios, and conflating them was the root cause of the logo appearing
  // cropped/wrong inside the (square) logo card.
  final String? imageUrl;
  // Square-ish logo mark shown in the white logo card overlapping the hero
  // boundary (see StoreInfoSection's `_VendorLogo`). Null means the vendor
  // hasn't uploaded one yet — render a neutral placeholder, never fall back
  // to [imageUrl] (that reintroduces the cropped-cover-photo-as-logo bug).
  final String? logoUrl;
  final bool isOpen;
  final VendorApprovalStatus approvalStatus;
  // Written only by the `onReviewCreated` Cloud Function trigger (Admin SDK,
  // bypasses firestore.rules) via FieldValue.increment — see the ratings
  // architecture note in CLAUDE.md. Owners cannot self-inflate these.
  final num ratingSum;
  final int ratingCount;
  final VendorCategory category;
  // Canonical `cities/{id}` document id (see models/city.dart) — a plain
  // string, not the retired `City` enum. Firestore already stored this as
  // a lowercase string before the enum was retired, so the wire format is
  // unchanged; only the Dart-side type changed.
  final String city;
  // Null means "not set by the vendor yet" — always render as an omitted
  // badge, never a fabricated 0/placeholder value.
  final double? deliveryFee;
  final int? etaMinMinutes;
  final int? etaMaxMinutes;
  final double? minimumOrderAmount;
  // "HH:mm" 24h, both null or both set — a single daily pair, not
  // per-day-of-week hours (not asked for). Null means the vendor hasn't set
  // hours yet: render real open/closed status from `isOpen` instead of a
  // fabricated time (see VendorMenuScreen's status line).
  final String? openTime;
  final String? closeTime;

  const Vendor({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.description,
    this.imageUrl,
    this.logoUrl,
    required this.isOpen,
    required this.approvalStatus,
    this.ratingSum = 0,
    this.ratingCount = 0,
    this.category = VendorCategory.groceries,
    this.city = 'damascus',
    this.deliveryFee,
    this.etaMinMinutes,
    this.etaMaxMinutes,
    this.minimumOrderAmount,
    this.openTime,
    this.closeTime,
  });

  double? get averageRating => ratingCount == 0 ? null : ratingSum / ratingCount;

  factory Vendor.fromMap(String id, Map<String, dynamic> map) {
    return Vendor(
      id: id,
      ownerId: map['ownerId'] as String,
      name: map['name'] as String,
      description: map['description'] as String,
      imageUrl: map['imageUrl'] as String?,
      logoUrl: map['logoUrl'] as String?,
      isOpen: map['isOpen'] as bool? ?? false,
      approvalStatus: enumByName(
        VendorApprovalStatus.values,
        map['approvalStatus'] as String? ?? 'pending',
      ),
      ratingSum: map['ratingSum'] as num? ?? 0,
      ratingCount: map['ratingCount'] as int? ?? 0,
      // Not enumByName: this field postdates every vendor doc written
      // before this release, so a missing/unrecognized value must fall
      // back quietly instead of throwing AppException(malformed-data) and
      // breaking watchOpenVendors() for every pre-existing vendor.
      category: VendorCategory.values.firstWhere(
        (c) => c.name == map['category'],
        orElse: () => VendorCategory.groceries,
      ),
      // Plain string passthrough — 'damascus' if missing, matching the
      // retired City enum's old default. A non-empty but unrecognized city
      // id (e.g. one belonging to a since-disabled/removed cities/{id} doc)
      // is preserved as-is rather than reset, so a vendor's own city
      // assignment is never silently overwritten by a display-layer gap —
      // see enum_labels.dart's cityLabel() for how that's still shown
      // safely.
      city: (map['city'] as String?) ?? 'damascus',
      deliveryFee: (map['deliveryFee'] as num?)?.toDouble(),
      etaMinMinutes: map['etaMinMinutes'] as int?,
      etaMaxMinutes: map['etaMaxMinutes'] as int?,
      minimumOrderAmount: (map['minimumOrderAmount'] as num?)?.toDouble(),
      openTime: map['openTime'] as String?,
      closeTime: map['closeTime'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'description': description,
      'imageUrl': imageUrl,
      'logoUrl': logoUrl,
      'isOpen': isOpen,
      'approvalStatus': approvalStatus.name,
      'ratingSum': ratingSum,
      'ratingCount': ratingCount,
      'category': category.name,
      'city': city,
      'deliveryFee': deliveryFee,
      'etaMinMinutes': etaMinMinutes,
      'etaMaxMinutes': etaMaxMinutes,
      'minimumOrderAmount': minimumOrderAmount,
      'openTime': openTime,
      'closeTime': closeTime,
    };
  }
}

class MenuItem {
  final String id;
  final String vendorId;
  final String name;
  final double price;
  final String? imageUrl;
  final bool available;
  final String? description;
  // Free-text, vendor-authored menu grouping (e.g. "Burgers", "Sides") —
  // deliberately not the fixed marketplace-wide VendorCategory enum, since
  // one store's own menu sections are its own business, not a taxonomy the
  // whole marketplace shares. Null groups the item into a generic fallback
  // section (see core/discovery/menu_sections.dart).
  final String? section;
  // Real, Admin-SDK-aggregated popularity — incremented by the
  // onOrderStatusChanged Cloud Function trigger when an order reaches
  // 'delivered' (see functions/src/orders.ts), same
  // client-cannot-self-inflate reasoning as Vendor.ratingSum/ratingCount.
  final int orderCount;

  const MenuItem({
    required this.id,
    required this.vendorId,
    required this.name,
    required this.price,
    this.imageUrl,
    required this.available,
    this.description,
    this.section,
    this.orderCount = 0,
  });

  factory MenuItem.fromMap(String id, Map<String, dynamic> map) {
    return MenuItem(
      id: id,
      vendorId: map['vendorId'] as String,
      name: map['name'] as String,
      price: (map['price'] as num).toDouble(),
      imageUrl: map['imageUrl'] as String?,
      available: map['available'] as bool? ?? true,
      description: map['description'] as String?,
      section: map['section'] as String?,
      orderCount: map['orderCount'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'vendorId': vendorId,
      'name': name,
      'price': price,
      'imageUrl': imageUrl,
      'available': available,
      'description': description,
      'section': section,
      'orderCount': orderCount,
    };
  }
}
