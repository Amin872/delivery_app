import 'dart:async';
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delivery_app/features/auth/providers/auth_provider.dart';
import 'package:delivery_app/features/customer/screens/customer_home_screen.dart'
    show allCitiesProvider, firestoreServiceProvider;
import 'package:delivery_app/features/driver/providers/driver_location_provider.dart';
import 'package:delivery_app/features/driver/screens/driver_home_screen.dart';
import 'package:delivery_app/features/driver/widgets/driver_proof_picker.dart';
import 'package:delivery_app/features/vendor/screens/menu_management_screen.dart' show storageServiceProvider;
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/models/approval_status.dart';
import 'package:delivery_app/models/city.dart';
import 'package:delivery_app/models/driver.dart';
import 'package:delivery_app/models/order.dart';
import 'package:delivery_app/services/firestore_service.dart';
import 'package:delivery_app/services/functions_service.dart';
import 'package:delivery_app/services/storage_service.dart';

// Realistic worst cases for the driver screens: a full-length Firestore id,
// long Arabic and English names, eight-digit SYP amounts, long mixed
// addresses and notes, several lines.
const driverId = 'd';
const longOrderId = 'Xk9QpL2mZt7RwY4bNcV1';
const longAr = 'شاورما دجاج عائلية كبيرة مع بطاطا مقلية وثومية ومخللات إضافية';
const longEn = 'Family-size chicken shawarma platter with fries, garlic sauce and pickles';

DeliveryOrder driverOrder(String id, OrderStatus status, {double total = 15013000, String? driverId}) =>
    DeliveryOrder(
      id: id,
      customerId: 'c',
      vendorId: 'v',
      driverId: driverId,
      items: const [
        OrderItem(menuItemId: 'a', name: longAr, quantity: 12, unitPrice: 1250000),
        OrderItem(menuItemId: 'b', name: longEn, quantity: 1, unitPrice: 3000),
        OrderItem(menuItemId: 'c', name: 'فلافل', quantity: 3, unitPrice: 1000),
      ],
      status: status,
      total: total,
      subtotal: total - 10000,
      deliveryFee: 10000,
      deliveryAddress: 'المزرعة، شارع عبد الرحمن الشهبندر، بناء 12، الطابق 3 — Building 12, 3rd floor',
      deliveryLatitude: 33.5138,
      deliveryLongitude: 36.2765,
      deliveryInstructions: 'الباب الأيسر بعد المصعد، يرجى الاتصال قبل الوصول بخمس دقائق',
      driverNote: 'Call on arrival, no doorbell',
      vendorName: 'مطعم الشام الكبير للمأكولات الشرقية والمشاوي الدمشقية',
      pickupAddress: 'باب توما، شارع القصاع، مقابل الكنيسة — Bab Touma, Qassaa St.',
      pickupLatitude: 33.5150,
      pickupLongitude: 36.3160,
      createdAt: DateTime(2026, 9, 22, 18, 30),
    );

Driver testDriver({ApprovalStatus status = ApprovalStatus.approved, bool available = true}) => Driver(
      id: driverId,
      userId: driverId,
      isAvailable: available,
      approvalStatus: status,
      lastKnownLocation: DriverLocation(latitude: 33.51, longitude: 36.30, updatedAt: DateTime.now()),
    );

class _MockFirebaseFunctions extends Mock implements FirebaseFunctions {}

class _MockFirebaseStorage extends Mock implements FirebaseStorage {}

/// Records the driver callables; [advanceError] makes advanceDelivery fail.
class RecordingFunctions extends FunctionsService {
  RecordingFunctions() : super(functions: _MockFirebaseFunctions());

  final advanced = <({String orderId, String? proofImageUrl})>[];
  final accepted = <String>[];

  @override
  Future<void> acceptDelivery(String orderId) async => accepted.add(orderId);

  @override
  Future<void> advanceDelivery(String orderId, {String? proofImageUrl}) async =>
      advanced.add((orderId: orderId, proofImageUrl: proofImageUrl));

  @override
  Future<String> getOrderContact(String orderId, ContactTarget target) async => '+963944123456';
}

/// Records proof uploads (order id + file) without touching Firebase.
class RecordingStorage extends StorageService {
  RecordingStorage() : super(storage: _MockFirebaseStorage());

  final uploads = <({String orderId, String path})>[];

  @override
  Future<String> uploadOrderProof(String orderId, File file) async {
    uploads.add((orderId: orderId, path: file.path));
    return 'https://example.test/orderProofs/$orderId/proof.jpg';
  }
}

/// setDriverAvailability that either fails or waits for [gate].
class ControlledFirestore extends FirestoreService {
  ControlledFirestore({this.fail = false}) : super(firestore: FakeFirebaseFirestore());

  final bool fail;
  final availabilityWrites = <bool>[];
  Completer<void> gate = Completer<void>()..complete();

  @override
  Future<void> setDriverAvailability(String driverId, bool isAvailable) async {
    availabilityWrites.add(isAvailable);
    await gate.future;
    if (fail) throw Exception('permission-denied: raw backend detail');
  }
}

/// A picker that records the requested sources and returns [result] (or
/// throws [error]).
class FakeProofPicker {
  FakeProofPicker({this.result, this.error});

  File? result;
  Object? error;
  final sources = <ImageSource>[];

  Future<File?> call(ImageSource source) async {
    sources.add(source);
    if (error != null) throw error!;
    return result;
  }
}

/// Everything DriverHomeScreen needs, as overrides. [activeOrders] feeds
/// the active delivery (a controller lets a test switch orders).
List<Override> driverHomeOverrides({
  Driver? driver,
  Stream<Driver>? driverStream,
  Stream<DeliveryOrder?>? activeOrders,
  List<DeliveryOrder> queue = const [],
  Stream<List<DeliveryOrder>>? queueStream,
  FirestoreService? firestore,
  FunctionsService? functions,
  StorageService? storage,
  FakeProofPicker? picker,
}) =>
    [
      allCitiesProvider.overrideWith((ref) => Stream.value(const <CityOption>[])),
      currentAppUserProvider.overrideWith((ref) => Stream.value(
          const AppUser(id: driverId, email: 'd@example.com', displayName: 'D', role: UserRole.driver))),
      driverSelfProvider(driverId).overrideWith((ref) => driverStream ?? Stream.value(driver ?? testDriver())),
      activeDriverOrderProvider(driverId).overrideWith((ref) => activeOrders ?? Stream.value(null)),
      // No GPS in widget tests.
      driverLocationSyncProvider(driverId).overrideWith((ref) {}),
      availableOrdersProvider.overrideWith((ref) => queueStream ?? Stream.value(queue)),
      if (firestore != null) firestoreServiceProvider.overrideWithValue(firestore),
      functionsServiceProvider.overrideWithValue(functions ?? RecordingFunctions()),
      storageServiceProvider.overrideWithValue(storage ?? RecordingStorage()),
      if (picker != null) proofPhotoPickerProvider.overrideWithValue(picker.call),
    ];

/// The home screen's scroll view.
Finder get driverHomeScroll => find.byType(Scrollable).first;

/// Scrolls [finder] into view inside the home screen's one scroll.
Future<void> revealInHome(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(finder, 200, scrollable: driverHomeScroll);
  await tester.pumpAndSettle();
}

/// Key of the Material "more" menu in the driver AppBar.
const driverMoreMenuKey = ValueKey('driver_more_menu');
