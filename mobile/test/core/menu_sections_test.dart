import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/discovery/menu_sections.dart';
import 'package:delivery_app/models/vendor.dart';

MenuItem _item(
  String id, {
  String? section,
  int orderCount = 0,
}) {
  return MenuItem(
    id: id,
    vendorId: 'vendor-1',
    name: 'Item $id',
    price: 10,
    available: true,
    section: section,
    orderCount: orderCount,
  );
}

void main() {
  group('mostOrderedItems', () {
    test('sorts by orderCount descending, excludes zero, respects limit', () {
      final items = [
        _item('a', orderCount: 5),
        _item('b'),
        _item('c', orderCount: 20),
        _item('d', orderCount: 10),
      ];

      final result = mostOrderedItems(items, limit: 2);

      expect(result.map((i) => i.id), ['c', 'd']);
    });

    test('returns an empty list when nothing has been ordered', () {
      expect(mostOrderedItems([_item('a')]), isEmpty);
    });
  });

  group('buildMenuSections', () {
    test('puts a non-empty "most ordered" section first, then groups by section '
        'in first-seen order, falling back to the default title', () {
      final items = [
        _item('burger-1', section: 'Burgers', orderCount: 15),
        _item('side-1', section: 'Sides'),
        _item('burger-2', section: 'Burgers'),
        _item('mystery-1'), // no section
      ];

      final sections = buildMenuSections(
        items,
        mostOrderedTitle: 'Most ordered',
        defaultSectionTitle: 'Menu',
      );

      expect(sections.map((s) => s.title), ['Most ordered', 'Burgers', 'Sides', 'Menu']);
      expect(sections[0].items.map((i) => i.id), ['burger-1']); // most ordered
      expect(sections[1].items.map((i) => i.id), ['burger-1', 'burger-2']); // Burgers
      expect(sections[2].items.map((i) => i.id), ['side-1']); // Sides
      expect(sections[3].items.map((i) => i.id), ['mystery-1']); // Menu fallback
      expect(sections.map((s) => s.isMostOrdered), [true, false, false, false]);
    });

    test('omits the "most ordered" section entirely when nothing qualifies', () {
      final items = [_item('a', section: 'Drinks')];

      final sections = buildMenuSections(
        items,
        mostOrderedTitle: 'Most ordered',
        defaultSectionTitle: 'Menu',
      );

      expect(sections.map((s) => s.title), ['Drinks']);
    });

    test('returns an empty list for an empty input', () {
      expect(
        buildMenuSections(const [], mostOrderedTitle: 'Most ordered', defaultSectionTitle: 'Menu'),
        isEmpty,
      );
    });
  });
}
