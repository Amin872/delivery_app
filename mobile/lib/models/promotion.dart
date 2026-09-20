import '../core/parsing/safe_enum.dart';

enum PromotionMediaType { image, video }

/// One admin-managed card in [PromoBannerCarousel] — replaces the previous
/// hardcoded, evergreen banner copy with real Firestore-backed content
/// (`promotions/{promotionId}`), following the same conventions as
/// [Vendor]/[MenuItem]: plain fields + `fromMap`/`toMap`.
class Promotion {
  final String id;
  final String? title;
  final String? description;
  final String mediaUrl;
  final PromotionMediaType mediaType;
  // Shown as a small CTA button only when both are set (see
  // PromoBannerCarousel) — first-cut scope: interpreted as a vendor id to
  // open via the existing VendorMenuScreen route, not a generic deep link.
  final String? ctaLabel;
  final String? ctaAction;
  final int order;
  final bool enabled;

  const Promotion({
    required this.id,
    this.title,
    this.description,
    required this.mediaUrl,
    required this.mediaType,
    this.ctaLabel,
    this.ctaAction,
    required this.order,
    required this.enabled,
  });

  factory Promotion.fromMap(String id, Map<String, dynamic> map) {
    return Promotion(
      id: id,
      title: map['title'] as String?,
      description: map['description'] as String?,
      mediaUrl: map['mediaUrl'] as String,
      mediaType: enumByName(PromotionMediaType.values, map['mediaType'] as String?),
      ctaLabel: map['ctaLabel'] as String?,
      ctaAction: map['ctaAction'] as String?,
      order: map['order'] as int? ?? 0,
      enabled: map['enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'mediaUrl': mediaUrl,
      'mediaType': mediaType.name,
      'ctaLabel': ctaLabel,
      'ctaAction': ctaAction,
      'order': order,
      'enabled': enabled,
    };
  }
}
