/// Admin review state shared by vendors and drivers — stored on both
/// `vendors/{vendorId}` and `drivers/{driverId}` under the same Firestore
/// field name, `approvalStatus`, with the same wire values (the enum's
/// `name`). New accounts always start [pending]; only an admin can move them
/// out of it (see the matching `allow update` branches in firestore.rules).
enum ApprovalStatus { pending, approved, rejected }

/// Parses a stored `approvalStatus` value, treating a missing, null, or
/// unrecognized value as [ApprovalStatus.pending] rather than throwing — the
/// fail-closed default, since pending grants no approved-only access. Used
/// for drivers, whose docs predate the field; vendors keep their own
/// stricter parsing in Vendor.fromMap.
ApprovalStatus approvalStatusFromWire(Object? value) {
  return ApprovalStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => ApprovalStatus.pending,
  );
}
