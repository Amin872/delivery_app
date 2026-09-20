import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../../../core/providers/formatters_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/widgets/app_network_image.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/vendor.dart';
import '../screens/vendor_menu_screen.dart' show vendorMenuProvider;
import 'cart_add_flow.dart';
import 'most_ordered_card.dart';
import 'product_order_bar.dart';
import 'store_header_action_button.dart';

const double _heroImageHeight = 300;

/// Opens [ProductDetailsSheet] as a modal bottom sheet — the single entry
/// point every product card (the horizontal "Most ordered" carousel, the
/// full "Most ordered" grid, normal vertical menu rows, and the
/// recommended-products grid inside this very sheet) taps into, so "tap a
/// product card" always means the same thing everywhere. Stacks a new sheet
/// on top rather than popping-then-pushing when opened from within another
/// sheet (recommended products) — simpler, and the X button naturally
/// reveals the sheet underneath via the normal route stack.
Future<void> showProductDetailsSheet(
  BuildContext context, {
  required String vendorId,
  required String vendorName,
  required MenuItem item,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => ProductDetailsSheet(
      vendorId: vendorId,
      vendorName: vendorName,
      item: item,
    ),
  );
}

/// Product details bottom sheet — see `showProductDetailsSheet`. Layout
/// order matches the reference exactly: drag handle, collapsing hero image
/// with a circular close button, name, price + info/share actions,
/// description, "اشترى آخرون أيضًا" recommended grid (reusing
/// `MostOrderedCard` — the reference uses the identical card design there),
/// "معلومات حول المنتج" / "إبلاغ" rows, and a fixed bottom order bar.
class ProductDetailsSheet extends ConsumerWidget {
  const ProductDetailsSheet({
    required this.vendorId,
    required this.vendorName,
    required this.item,
    super.key,
  });

  final String vendorId;
  final String vendorName;
  final MenuItem item;

  void _showProductInfo(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.productInfoSectionLabel),
        content: Text(item.description ?? l10n.noDescriptionPlaceholder),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.confirmButton),
          ),
        ],
      ),
    );
  }

  void _shareProduct(BuildContext context, NumberFormat currencyFormat) {
    final l10n = AppLocalizations.of(context)!;
    final text = '${item.name} — ${currencyFormat.format(item.price)}';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.productDetailsCopiedMessage)));
  }

  void _submitReport(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.reportSubmittedMessage)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final vendorTheme = VendorPalette.themeFrom(Theme.of(context));
    final currencyFormat = ref.watch(currencyFormatProvider);
    final menuAsync = ref.watch(vendorMenuProvider(vendorId));
    final colorScheme = vendorTheme.colorScheme;

    return Theme(
      data: vendorTheme,
      child: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.bottomCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 700),
            child: FractionallySizedBox(
              heightFactor: 0.94,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
                child: ColoredBox(
                  color: VendorPalette.background,
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                        child: _DragHandle(),
                      ),
                      Expanded(
                        child: Stack(
                          children: [
                            CustomScrollView(
                              slivers: [
                                SliverAppBar(
                                  pinned: true,
                                  automaticallyImplyLeading: false,
                                  backgroundColor: VendorPalette.background,
                                  expandedHeight: _heroImageHeight,
                                  flexibleSpace: FlexibleSpaceBar(
                                    centerTitle: false,
                                    titlePadding:
                                        const EdgeInsetsDirectional.only(
                                          start: 72,
                                          bottom: 16,
                                          end: 16,
                                        ),
                                    title: Text(
                                      item.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    background: item.imageUrl != null
                                        ? AppNetworkImage(
                                            imageUrl: item.imageUrl!,
                                            fit: BoxFit.cover,
                                          )
                                        : Container(
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.fastfood_outlined,
                                              size: 48,
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.lg,
                                      AppSpacing.xl,
                                      AppSpacing.lg,
                                      0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.name,
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                color:
                                                    VendorPalette.textPrimary,
                                              ),
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                        Row(
                                          // First child renders at the RTL start
                                          // (right), matching the reference's
                                          // price-on-the-right / actions-on-the-
                                          // left arrangement.
                                          children: [
                                            Text(
                                              currencyFormat.format(item.price),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge
                                                  ?.copyWith(
                                                    color:
                                                        mostOrderedAccentForeground,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                            ),
                                            const Spacer(),
                                            StoreHeaderActionButton(
                                              icon: Icons.info_outline,
                                              tooltip: l10n.productInfoTooltip,
                                              onPressed: () =>
                                                  _showProductInfo(context),
                                            ),
                                            StoreHeaderActionButton(
                                              icon: Icons.ios_share,
                                              tooltip: l10n.shareTooltip,
                                              onPressed: () => _shareProduct(
                                                context,
                                                currencyFormat,
                                              ),
                                            ),
                                          ],
                                        ),
                                        if (item.description != null) ...[
                                          const SizedBox(height: AppSpacing.lg),
                                          Text(
                                            item.description!,
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyLarge
                                                ?.copyWith(
                                                  color: VendorPalette
                                                      .textSecondary,
                                                ),
                                          ),
                                        ],
                                        const SizedBox(height: AppSpacing.lg),
                                        Divider(color: VendorPalette.divider),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: AppSpacing.sm,
                                          ),
                                          child: Text(
                                            l10n.alsoBoughtTitle,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                menuAsync.when(
                                  data: (items) {
                                    final recommended = items
                                        .where(
                                          (other) =>
                                              other.id != item.id &&
                                              other.available,
                                        )
                                        .toList();
                                    if (recommended.isEmpty) {
                                      return const SliverToBoxAdapter(
                                        child: SizedBox.shrink(),
                                      );
                                    }
                                    return SliverPadding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.lg,
                                      ),
                                      sliver: SliverLayoutBuilder(
                                        builder: (context, constraints) {
                                          const gap = AppSpacing.sm;
                                          final cardWidth =
                                              (constraints.crossAxisExtent -
                                                  gap) /
                                              2;
                                          return SliverGrid(
                                            gridDelegate:
                                                SliverGridDelegateWithFixedCrossAxisCount(
                                                  crossAxisCount: 2,
                                                  crossAxisSpacing: gap,
                                                  mainAxisSpacing: gap,
                                                  childAspectRatio:
                                                      mostOrderedCardAspectRatioForWidth(
                                                        cardWidth,
                                                      ),
                                                ),
                                            delegate: SliverChildBuilderDelegate((
                                              context,
                                              index,
                                            ) {
                                              final recommendedItem =
                                                  recommended[index];
                                              return MostOrderedCard(
                                                item: recommendedItem,
                                                currencyFormat: currencyFormat,
                                                onAddToCart: () =>
                                                    addToCartWithVendorSwitchConfirm(
                                                      context,
                                                      ref,
                                                      vendorId: vendorId,
                                                      vendorName: vendorName,
                                                      item: recommendedItem,
                                                    ),
                                                onTap: () =>
                                                    showProductDetailsSheet(
                                                      context,
                                                      vendorId: vendorId,
                                                      vendorName: vendorName,
                                                      item: recommendedItem,
                                                    ),
                                              );
                                            }, childCount: recommended.length),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                  loading: () => const SliverToBoxAdapter(
                                    child: SizedBox.shrink(),
                                  ),
                                  error: (_, __) => const SliverToBoxAdapter(
                                    child: SizedBox.shrink(),
                                  ),
                                ),
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      AppSpacing.lg,
                                      AppSpacing.lg,
                                      AppSpacing.lg,
                                      0,
                                    ),
                                    child: Column(
                                      children: [
                                        Divider(color: VendorPalette.divider),
                                        _InfoRow(
                                          label: l10n.productInfoSectionLabel,
                                          onTap: () =>
                                              _showProductInfo(context),
                                        ),
                                        Divider(color: VendorPalette.divider),
                                        _InfoRow(
                                          label: l10n.reportSectionLabel,
                                          onTap: () => _submitReport(context),
                                        ),
                                        const SizedBox(height: AppSpacing.lg),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Deliberately a literal top-left overlay (not
                            // SliverAppBar.leading, which mirrors to the
                            // right under RTL) — pinned above the scroll
                            // content so it stays put through both the
                            // expanded hero and the collapsed toolbar state,
                            // matching the reference in both screenshots.
                            Positioned(
                              top: 4,
                              left: 8,
                              child: StoreHeaderActionButton(
                                icon: Icons.close,
                                tooltip: l10n.closeTooltip,
                                onPressed: () =>
                                    Navigator.of(context).maybePop(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ProductOrderBar(
                        vendorId: vendorId,
                        vendorName: vendorName,
                        item: item,
                        currencyFormat: currencyFormat,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: VendorPalette.textMuted,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// "معلومات حول المنتج" / "إبلاغ" disclosure row — right-aligned label with
/// a leading (visually left, matching the reference) chevron.
class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            // Unflipped renders "<" under this screen's RTL Directionality —
            // same verified-live convention as MostOrderedSection's arrow.
            Transform.flip(
              flipX: Directionality.of(context) != TextDirection.rtl,
              child: Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: VendorPalette.textSecondary,
              ),
            ),
            const Spacer(),
            Text(
              label,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: VendorPalette.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
