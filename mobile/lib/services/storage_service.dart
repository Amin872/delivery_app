import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/guard.dart';

/// Thin wrapper around Firebase Storage, mirroring the plain-class +
/// optional-injected-instance pattern used by AuthService/FirestoreService.
class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads [file] to `vendorImages/{vendorId}/{fileName}` and returns its
  /// download URL. Callers pass a stable [fileName] (e.g. `storefront.jpg`,
  /// `menu_{itemId}.jpg`) so re-uploading replaces the previous image
  /// instead of accumulating orphaned files. Matches the storage.rules match
  /// block that scopes writes here to that vendor's owner.
  Future<String> uploadVendorImage(String vendorId, File file, String fileName) {
    return guardFuture(() async {
      final ref = _storage.ref('vendorImages/$vendorId/$fileName');
      await ref.putFile(file);
      return ref.getDownloadURL();
    });
  }

  /// Uploads [file] to `orderProofs/{orderId}/proof.jpg` and returns its
  /// download URL. storage.rules scopes writes here to the order's assigned
  /// driver — this only succeeds once the caller is that driver, independent
  /// of and prior to the `advanceDelivery` callable that records the URL.
  Future<String> uploadOrderProof(String orderId, File file) {
    return guardFuture(() async {
      final ref = _storage.ref('orderProofs/$orderId/proof.jpg');
      await ref.putFile(file);
      return ref.getDownloadURL();
    });
  }
}
