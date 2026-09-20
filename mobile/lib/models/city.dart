/// Cities this delivery marketplace operates in — a small fixed set, mirroring
/// [VendorCategory]'s shape. Used both as a field on [Vendor] (which city a
/// vendor operates in) and as the customer's browsing preference (see
/// `selectedCityProvider` in `core/providers/preferences_provider.dart`).
enum City { damascus, aleppo, homs, latakia, tartus }
