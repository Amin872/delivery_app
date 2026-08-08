import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

import '../core/errors/guard.dart';

/// Thin wrapper around Firebase Storage, mirroring the plain-class +
/// optional-injected-instance pattern used by AuthService/FirestoreService.
/// Every path here lands under `vendorImages/{vendorId}/`, matching the
/// storage.rules match block that scopes writes to that vendor's owner.
class StorageService {
  StorageService({FirebaseStorage? storage}) : _storage = storage ?? FirebaseStorage.instance;

  final FirebaseStorage _storage;

  /// Uploads [file] to `vendorImages/{vendorId}/{fileName}` and returns its
  /// download URL. Callers pass a stable [fileName] (e.g. `storefront.jpg`,
  /// `menu_{itemId}.jpg`) so re-uploading replaces the previous image
  /// instead of accumulating orphaned files.
  Future<String> uploadVendorImage(String vendorId, File file, String fileName) {
    return guardFuture(() async {
      final ref = _storage.ref('vendorImages/$vendorId/$fileName');
      await ref.putFile(file);
      return ref.getDownloadURL();
    });
  }
}
