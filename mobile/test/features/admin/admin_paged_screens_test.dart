import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delivery_app/core/paging/page_result.dart';
import 'package:delivery_app/features/admin/screens/admin_products_screen.dart';
import 'package:delivery_app/features/admin/screens/admin_users_screen.dart';
import 'package:delivery_app/features/admin/widgets/admin_actions.dart';
import 'package:delivery_app/models/app_user.dart';
import 'package:delivery_app/services/firestore_service.dart';

import 'admin_test_harness.dart';

/// Records each Users page request; the first request can fail.
class _UsersService extends FirestoreService {
  _UsersService(FakeFirebaseFirestore db, {this.failFirst = false}) : super(firestore: db);

  bool failFirst;
  final searches = <String>[];

  @override
  Future<PageResult<AppUser>> fetchUsersPage({String search = '', Object? after, int limit = kAdminPageSize}) {
    searches.add(search);
    if (failFirst) {
      failFirst = false;
      return Future.error(Exception('unavailable'));
    }
    return super.fetchUsersPage(search: search, after: after, limit: limit);
  }
}

Future<FakeFirebaseFirestore> _usersDb() async {
  final db = FakeFirebaseFirestore();
  Future<void> user(String id, String name, String email) =>
      db.collection('users').doc(id).set({'email': email, 'displayName': name, 'role': 'customer'});
  await user('u1', 'Rana Haddad', 'rana@example.com');
  await user('u2', 'Omar Saleh', 'omar@example.com');
  await user('u3', 'Rami Khoury', 'rami@example.com');
  return db;
}

Future<void> _search(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(AdminSearchField.debounce);
  await tester.pumpAndSettle();
}

void main() {
  group('AdminUsersScreen', () {
    testWidgets('searches on the server after typing pauses; clearing restores the full list', (tester) async {
      final db = await _usersDb();
      final service = _UsersService(db);
      await pumpAdminScreen(tester, const AdminUsersScreen(), db, service: service);
      expect(find.byType(ListTile), findsNWidgets(3));

      // Typing doesn't query per keystroke: nothing is sent before the pause.
      await tester.enterText(find.byType(TextField), 'Ra');
      await tester.pump(const Duration(milliseconds: 100));
      expect(service.searches, ['']);
      await tester.pump(AdminSearchField.debounce);
      await tester.pumpAndSettle();
      expect(service.searches, ['', 'Ra']);
      expect(find.text('Rana Haddad'), findsOneWidget);
      expect(find.text('Rami Khoury'), findsOneWidget);
      expect(find.text('Omar Saleh'), findsNothing);

      await tester.tap(find.byTooltip(adminTestL10n.clearSearchTooltip));
      await tester.pumpAndSettle();
      expect(service.searches.last, '');
      expect(find.byType(ListTile), findsNWidgets(3));
    });

    testWidgets('an email search (with "@") matches the email prefix', (tester) async {
      final db = await _usersDb();
      await pumpAdminScreen(tester, const AdminUsersScreen(), db);
      await _search(tester, 'omar@');
      expect(find.text('Omar Saleh'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
    });

    testWidgets('no match shows the empty message', (tester) async {
      final db = await _usersDb();
      await pumpAdminScreen(tester, const AdminUsersScreen(), db);
      await _search(tester, 'Zz');
      expect(find.text(adminTestL10n.noUsersFoundMessage), findsOneWidget);
    });

    testWidgets('a failed first page shows the shared error with a working Retry', (tester) async {
      final db = await _usersDb();
      await pumpAdminScreen(tester, const AdminUsersScreen(), db, service: _UsersService(db, failFirst: true));
      expect(find.text(adminTestL10n.retryButton), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);

      await tester.tap(find.text(adminTestL10n.retryButton));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(3));
    });
  });

  group('AdminProductsScreen', () {
    Future<FakeFirebaseFirestore> productsDb() async {
      final db = FakeFirebaseFirestore();
      Future<void> vendor(String id, String name) => db.collection('vendors').doc(id).set({
            'ownerId': 'o-$id',
            'name': name,
            'description': '',
            'isOpen': true,
            'approvalStatus': 'approved',
          });
      Future<void> item(String vendorId, String id, String name, bool available) =>
          db.collection('vendors').doc(vendorId).collection('menuItems').doc(id).set({
            'vendorId': vendorId,
            'name': name,
            'price': 1000,
            'available': available,
          });
      await vendor('v1', 'Falafel House');
      await vendor('v2', 'Pizza Place');
      await item('v1', 'i1', 'Falafel wrap', true);
      await item('v2', 'i1', 'Margherita', false); // same item id, other vendor
      return db;
    }

    testWidgets('lists every vendor\'s products with their vendor names', (tester) async {
      await pumpAdminScreen(tester, const AdminProductsScreen(), await productsDb());

      expect(find.text('Falafel wrap'), findsOneWidget);
      expect(find.text('Margherita'), findsOneWidget); // not de-duplicated by item id alone
      expect(find.textContaining('Falafel House'), findsOneWidget);
      expect(find.textContaining('Pizza Place'), findsOneWidget);
    });

    testWidgets('availability chips and the name search filter on the server', (tester) async {
      await pumpAdminScreen(tester, const AdminProductsScreen(), await productsDb());

      await tester.tap(find.widgetWithText(ChoiceChip, adminTestL10n.unavailableLabel));
      await tester.pumpAndSettle();
      expect(find.text('Margherita'), findsOneWidget);
      expect(find.text('Falafel wrap'), findsNothing);

      await tester.tap(find.widgetWithText(ChoiceChip, adminTestL10n.allStatusesLabel));
      await tester.pumpAndSettle();
      await _search(tester, 'Fal');
      expect(find.text('Falafel wrap'), findsOneWidget);
      expect(find.text('Margherita'), findsNothing);
    });
  });
}
