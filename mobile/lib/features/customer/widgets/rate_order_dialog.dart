import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/error_messages.dart';
import '../../../core/widgets/app_spinner.dart';
import '../../../core/widgets/star_rating.dart';
import '../../../l10n/app_localizations.dart';
import '../../../models/order.dart';
import '../../../models/review.dart';
import '../../auth/providers/auth_provider.dart';
import '../screens/customer_home_screen.dart' show firestoreServiceProvider;

/// Shown from `OrderTrackingScreen` once an order reaches `delivered` and
/// hasn't been reviewed yet. Submits straight to `FirestoreService.submitReview`
/// itself (rather than returning a value for the caller to act on) so it can
/// own its own loading/error state on the submit button, popping `true` only
/// once the write actually succeeds.
class RateOrderDialog extends ConsumerStatefulWidget {
  const RateOrderDialog({required this.order, super.key});

  final DeliveryOrder order;

  @override
  ConsumerState<RateOrderDialog> createState() => _RateOrderDialogState();
}

class _RateOrderDialogState extends ConsumerState<RateOrderDialog> {
  int _vendorRating = 5;
  int _driverRating = 5;
  final _commentController = TextEditingController();
  bool _submitting = false;
  Object? _error;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final order = widget.order;
    final customerId = ref.read(currentAppUserProvider).valueOrNull?.id;
    if (customerId == null || order.driverId == null) return;

    HapticFeedback.lightImpact();
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final comment = _commentController.text.trim();
      await ref.read(firestoreServiceProvider).submitReview(Review(
            id: order.id,
            orderId: order.id,
            customerId: customerId,
            vendorId: order.vendorId,
            driverId: order.driverId!,
            vendorRating: _vendorRating,
            driverRating: _driverRating,
            comment: comment.isEmpty ? null : comment,
            createdAt: DateTime.now(),
          ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      setState(() {
        _error = error;
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final error = _error;
    return AlertDialog(
      title: Text(l10n.rateOrderDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.vendorRatingLabel, style: Theme.of(context).textTheme.titleSmall),
          StarRatingInput(
            value: _vendorRating,
            onChanged: (value) => setState(() => _vendorRating = value),
          ),
          const SizedBox(height: 8),
          Text(l10n.driverRatingLabel, style: Theme.of(context).textTheme.titleSmall),
          StarRatingInput(
            value: _driverRating,
            onChanged: (value) => setState(() => _driverRating = value),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _commentController,
            decoration: InputDecoration(labelText: l10n.reviewCommentLabel),
            maxLines: 2,
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              localizedErrorMessage(context, error),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: Text(l10n.cancelButton),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? buttonSpinner(Theme.of(context).colorScheme.onPrimary, size: 16)
              : Text(l10n.submitReviewButton),
        ),
      ],
    );
  }
}
