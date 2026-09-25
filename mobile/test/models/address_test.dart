import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/models/address.dart';

void main() {
  test('SavedAddress round-trips through toMap/fromMap', () {
    final address = SavedAddress(
      id: 'addr-1',
      userId: 'user-1',
      label: 'Home',
      latitude: 33.5138,
      longitude: 36.2765,
      governorateId: 'damascus',
      cityId: 'damascus',
      neighborhoodId: 'damascus_mazzeh',
      addressText: 'Al-Mazzeh, near the pharmacy',
      deliveryInstructions: '3rd floor, blue gate',
      driverNote: 'Call on arrival',
      phone: '0999999999',
      isDefault: true,
      createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(2000),
    );

    final restored = SavedAddress.fromMap(address.id, address.toMap());

    expect(restored.userId, address.userId);
    expect(restored.label, address.label);
    expect(restored.latitude, address.latitude);
    expect(restored.longitude, address.longitude);
    expect(restored.governorateId, address.governorateId);
    expect(restored.cityId, address.cityId);
    expect(restored.neighborhoodId, address.neighborhoodId);
    expect(restored.addressText, address.addressText);
    expect(restored.deliveryInstructions, address.deliveryInstructions);
    expect(restored.driverNote, address.driverNote);
    expect(restored.phone, address.phone);
    expect(restored.isDefault, address.isDefault);
    expect(restored.createdAt, address.createdAt);
    expect(restored.updatedAt, address.updatedAt);
  });

  test('coordinates is null when either latitude or longitude is missing', () {
    const address = SavedAddress(
      id: 'addr-1',
      userId: 'user-1',
      label: 'Home',
      addressText: 'Some address',
    );

    expect(address.coordinates, isNull);
  });

  test('coordinates resolves when both latitude and longitude are set', () {
    const address = SavedAddress(
      id: 'addr-1',
      userId: 'user-1',
      label: 'Home',
      latitude: 33.5,
      longitude: 36.3,
      addressText: 'Some address',
    );

    expect(address.coordinates?.latitude, 33.5);
    expect(address.coordinates?.longitude, 36.3);
  });

  test('fromMap parses a pre-Phase-4 doc with no latitude/longitude/timestamps/userId', () {
    // Exactly the shape the old DeliveryAddress.toMap() used to write —
    // label/address/isDefault only. Must parse without throwing.
    final restored = SavedAddress.fromMap('addr-1', {
      'label': 'Home',
      'address': 'Damascus, Al-Mazzeh, near the pharmacy',
      'isDefault': true,
    });

    expect(restored.userId, '');
    expect(restored.label, 'Home');
    expect(restored.addressText, 'Damascus, Al-Mazzeh, near the pharmacy');
    expect(restored.isDefault, isTrue);
    expect(restored.latitude, isNull);
    expect(restored.longitude, isNull);
    expect(restored.coordinates, isNull);
    expect(restored.createdAt, isNull);
    expect(restored.updatedAt, isNull);
  });

  test('fromMap prefers addressText over the legacy address field when both are present', () {
    final restored = SavedAddress.fromMap('addr-1', {
      'label': 'Home',
      'address': 'legacy text',
      'addressText': 'new text',
    });

    expect(restored.addressText, 'new text');
  });

  test('copyWith overrides only the given fields, keeping the rest unchanged', () {
    const address = SavedAddress(
      id: 'addr-1',
      userId: 'user-1',
      label: 'Home',
      addressText: 'Some address',
      isDefault: false,
    );

    final updated = address.copyWith(isDefault: true, label: 'Work');

    expect(updated.id, address.id);
    expect(updated.userId, address.userId);
    expect(updated.addressText, address.addressText);
    expect(updated.label, 'Work');
    expect(updated.isDefault, isTrue);
  });
}
