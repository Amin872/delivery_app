import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/animated_async.dart';
import '../../../core/widgets/responsive_center.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/staggered_list_item.dart';
import '../../../l10n/app_localizations.dart';
import '../../../routing/page_transitions.dart';
import '../../auth/providers/auth_provider.dart';
import '../widgets/store_card.dart';
import 'customer_home_screen.dart' show openVendorsProvider;
import 'vendor_menu_screen.dart';

/// The signed-in customer's favorited vendors — real data, filtered from the
/// same `openVendorsProvider` stream CustomerHomeScreen already watches, by
/// `AppUser.favoriteVendorIds` (toggled via the heart button on
/// VendorMenuScreen). No separate collection/query needed.
///
/// Uses the same [VendorPalette] theme as CustomerHomeScreen/StoreListScreen
/// — [StoreCard] already hardcodes those colors directly (it doesn't read
/// `Theme.of(context)` at all), so this screen must wrap itself the same way
/// those screens do or its cards would mismatch an ambient-themed scaffold.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final vendorsAsync = ref.watch(openVendorsProvider);
    final favoriteIds = ref.watch(currentAppUserProvider).valueOrNull?.favoriteVendorIds ?? const [];
    final currencyFormat = ref.watch(currencyFormatProvider);
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));

    return Theme(
      data: vendorTheme,
      child: Scaffold(
        backgroundColor: VendorPalette.background,
        appBar: AppBar(
          backgroundColor: VendorPalette.background,
          foregroundColor: VendorPalette.textPrimary,
          title: Text(l10n.favoritesTitle),
        ),
        body: ResponsiveCenter(
          child: vendorsAsync.animatedWhen(
            data: (vendors) {
              final favorites = vendors.where((v) => favoriteIds.contains(v.id)).toList();
              if (favorites.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noFavoritesMessage,
                    style: const TextStyle(color: VendorPalette.textSecondary),
                  ),
                );
              }
              // Card height is derived from the actual available width via
              // the same formula StoreListScreen/StoreCarousel use for
              // StoreCard, rather than a guessed fixed height — a hardcoded
              // height here was always shorter than StoreCard's real content
              // (image + name + rating + divider + footer) on any real
              // device width, which is what caused the debug-mode
              // yellow/black RenderFlex overflow stripe at the bottom of
              // every card.
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth = constraints.maxWidth - AppSpacing.lg * 2;
                  final cardHeight = cardWidth / storeCardImageAspectRatio + storeCardBodyHeight;

                  return ListView.builder(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: favorites.length,
                    itemBuilder: (context, index) {
                      final vendor = favorites[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.md),
                        child: SizedBox(
                          height: cardHeight,
                          child: StoreCard(
                            vendor: vendor,
                            currencyFormat: currencyFormat,
                            onTap: () => Navigator.of(context)
                                .push(fadeSlideRoute(VendorMenuScreen(vendor: vendor))),
                          ),
                        ),
                      ).staggeredEntrance(index);
                    },
                  );
                },
              );
            },
            loading: () => const ListSkeletonLoader(),
            error: (error, _) => Center(
              child: Text(
                localizedErrorMessage(context, error),
                style: const TextStyle(color: VendorPalette.textSecondary),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
