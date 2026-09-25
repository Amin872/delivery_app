# Admin Panel — Full Architecture Investigation & Plan
*(Investigation and planning only — no code, rules, or files were changed as part of producing this report)*

---

## 1. Dashboard / Overview

**Exists:** Nothing. `AdminDashboardScreen` (`mobile/lib/features/admin/screens/admin_dashboard_screen.dart`) shows only a pending-vendors list — no stat cards, no counts, no alerts panel.

**Reusable:** `FirestoreService.countVendorOrders`/`sumVendorDeliveredSales`/`countVendorDeliveredOrders`/`countDriverDeliveries` (`mobile/lib/services/firestore_service.dart`) already use Firestore's `.count()`/`.aggregate(sum(...))` server-side aggregation — but they're all **scoped to one vendor/driver at a time** (used by `VendorStatsScreen`/`DriverStatsScreen`). None of them are marketplace-wide. `core/widgets/stat_card.dart` (`StatCard` widget) already exists and is exactly the visual building block an overview grid would use — it's currently used on the vendor/driver stats screens.

**Missing:** every marketplace-wide count (total users, total vendors, total drivers, orders today/week/month, revenue, active promotions) and any "alerts" concept. No collection or aggregation exists for any of these.

**Firestore collections involved:** `users`, `vendors`, `drivers`, `orders`, `promotions` (all exist; none are aggregated at marketplace scope today).

**Security implication:** every one of these counts requires a *marketplace-wide* read, which for `users` is not currently permitted at all (see §15) — this is the single biggest rules gap the whole plan depends on.

---

## 2. Customer/User Management

**Exists:** Nothing admin-facing. `users/{userId}` is only ever read/written for the signed-in user's own doc (`edit_profile_screen.dart`, `auth_service.dart`, `push_notification_service.dart`).

**Reusable:** `AppUser` model (`mobile/lib/models/app_user.dart`) already has `id`, `email`, `displayName`, `role`, `phoneNumber`, `favoriteVendorIds` — enough to render a list/detail view as-is. `FirestoreService.watchCustomerOrders(customerId)` already exists for "view user's orders." The list/search/filter UI pattern from `AdminOrdersScreen` (ChoiceChip filter row + `ListView.builder`) is directly reusable.

**Missing:** any way to list *all* users, search, view a user's own registration date (`AppUser` has no `createdAt` field at all today), enable/disable (`AppUser` has no `disabled`/`isActive` field), delete-other-user's-account (only self-delete exists in `AuthService.deleteAccount()`), and role-change UI.

**Firestore:** `users/{userId}` (exists, but admin currently cannot even *read* another user's doc — see §15).

**Storage:** none.

**Dependencies:** none new.

**Security changes eventually required:**
- `firestore.rules`: `users/{userId}` `allow read` needs `|| hasRole('admin')` added — it currently has none.
- A new `disabled: bool` field would need a matching admin-only-write carve-out (same `diff().affectedKeys().hasOnly([...])` pattern already used for `vendors.approvalStatus`).
- Deleting another user's Firestore doc via a client rule is risky (doesn't cascade to Firebase Auth); this really wants a Cloud Function callable (Admin SDK) rather than a rules change, mirroring how `acceptDelivery` was deliberately kept server-side instead of a client rule.
- Role changes must **never** be a client-writable field for the target's own doc (`users.update` rule already pins `role` — correctly leave that as-is); an admin role-change should go through a callable too, not a relaxed client rule, to avoid ever giving any signed-in client a path to self-promote.

---

## 3. Vendor / Store Management

**Exists (partial):** `AdminDashboardScreen`'s vendor-approvals list — `watchPendingVendors()`, approve/reject via `setVendorApprovalStatus()`.

**Exact files:** `mobile/lib/features/admin/screens/admin_dashboard_screen.dart`.

**Reusable:** `Vendor` model, `FirestoreService.watchVendor`/`updateVendorDetails`/`setVendorOpen`/`updateVendorImage` all already exist (built for the vendor's own dashboard, `vendor_dashboard_screen.dart`) — an admin "edit vendor" screen could call the exact same methods once rules allow admin as a caller. `menu_management_screen.dart`'s list+form pattern is the direct template for "view store products" from the admin side.

**Missing:** viewing approved/rejected vendors (not just pending), an admin edit-details screen, enable/disable a store independent of the owner, viewing a store's orders from the admin side (though `watchVendorOrders(vendorId)` already exists and could be reused as-is), and any concept of "store verification" beyond the existing `pending/approved/rejected` enum.

**Firestore:** `vendors/{vendorId}`, `vendors/{vendorId}/menuItems/{itemId}`.

**Storage:** `vendorImages/{vendorId}/{fileName}` (already admin-irrelevant — write is owner-only today).

**Security changes eventually required:** `vendors.update` rule's admin branch currently only allows changing `approvalStatus`. Letting admin also toggle `isOpen` (enable/disable) or edit other fields needs the `affectedKeys().hasOnly([...])` list widened deliberately, field by field — not a blanket admin-can-write-anything rule.

---

## 4. Driver Management

**Exists:** Nothing admin-facing at all — no admin screen references `drivers/{driverId}` anywhere.

**Reusable:** `Driver` model, `FirestoreService.watchDriver`/`setDriverAvailability` exist (built for the driver's own home screen). `watchActiveDriverOrder(driverId)` exists for "orders assigned to driver." `countDriverDeliveries(driverId)` exists for basic stats.

**Missing:** driver list, any approval/application concept (drivers currently self-register via signup with `role: driver` and are immediately usable — there's no `pending` state for drivers the way there is for vendors), enable/disable, and an admin driver-detail screen.

**Firestore:** `drivers/{driverId}` (read is already `isSignedIn()` — broad enough that admin can already read every driver doc today; only *write* needs an admin carve-out).

**Storage:** none.

**Security changes eventually required:** `drivers.update` rule is `isSelf(driverId)`-only; an admin enable/disable field needs the same kind of narrow `hasOnly([...])` admin branch as `vendors`. If a driver "application/approval" workflow is added (mirroring vendor approval), that's a new field (`approvalStatus`) plus a matching rule branch, plus `AuthService.signUp` would need to stop auto-activating drivers.

---

## 5. Order Management

**Exists (partial):** `AdminOrdersScreen` — view all orders, filter by `OrderStatus`, tap into `OrderTrackingScreen` (read-only).

**Exact file:** `mobile/lib/features/admin/screens/admin_orders_screen.dart`.

**Reusable:** `DeliveryOrder`/`OrderItem` models already carry everything requested (customer/vendor/driver ids, items, delivery address, status, total) — `OrderTrackingScreen` (customer-facing) already renders most of this and could be a template for a richer admin order-detail view. `FirestoreService.watchAllOrders(status:)` already powers the list.

**Missing:** admin cancel/reassign. There is genuinely no backend path for this today — `cancelOrder()` only lets the *customer* cancel their own still-`pending` order; `acceptDelivery`/`advanceDelivery` (in `functions/src/orders.ts`) are driver-invoked callables. No `adminCancelOrder`/`adminReassignDriver` callable exists.

**Firestore:** `orders/{orderId}` (already fully readable by admin, per `hasRole('admin')` in the read rule).

**Cloud Functions:** `functions/src/orders.ts` — `onOrderCreated`, `onOrderStatusChanged`, `acceptDelivery`, `advanceDelivery`. None are admin-callable today.

**Security/architecture changes eventually required:** Any admin intervention (force-cancel, reassign driver, refund) should be a **new Cloud Functions callable** (Admin SDK, transaction-guarded), following the exact same reasoning CLAUDE.md documents for `acceptDelivery`: race-sensitive state changes go through a callable, not a relaxed client rule. A client-side `orders.update` rule change for admin would be the wrong shape here.

---

## 6. Product Management

**Exists:** Fully implemented, but **vendor-side only** — `menu_management_screen.dart` (`mobile/lib/features/vendor/screens/menu_management_screen.dart`) already has add/edit/delete, availability toggle, image upload, price, description, section — everything the spec asks for, just scoped to `MenuItem.vendorId` matching the signed-in vendor.

**Missing (admin side):** any admin visibility into products across vendors, or an admin override to edit/delist a specific vendor's product.

**Firestore:** `vendors/{vendorId}/menuItems/{itemId}` (already publicly readable; the collection-group `menuItems` read is also public — `FirestoreService.watchAllMenuItems()` already exists and already returns every product across every vendor, so an admin product browser needs **zero new reads**, just new UI).

**Storage:** `vendorImages/{vendorId}/{fileName}` (menu photos share this path with storefront photos, keyed by filename).

**Security changes eventually required:** `menuItems` `update`/`delete` rules are owner-only (`get(...).data.ownerId == request.auth.uid`); an admin override needs `|| hasRole('admin')` added to those two rule branches specifically (read is already public, create is arguably fine staying owner-only).

---

## 7. Category Management

**Exists:** Not Firestore data at all — `VendorCategory` is a fixed Dart `enum` (`groceries, restaurants, bakery, drinks, pharmacy`) in `mobile/lib/models/vendor.dart`. Category labels come from `mobile/lib/core/l10n/enum_labels.dart` (`vendorCategoryLabel`), and category-based Home sections come from `core/discovery/vendor_carousels.dart`'s `vendorsInCategory()`/`selfcareVendors()` pure functions.

**Missing:** literally everything — there is no `categories` collection, no admin CRUD, no per-category image/icon field, no enable/disable.

**Migration implications (important, since this is architecturally invasive):** `Vendor.category` is typed as `VendorCategory` (an enum) throughout the codebase — `Vendor.fromMap`/`toMap`, `firestore.rules` doesn't touch it directly (no rule depends on category value), but `enum_labels.dart`, `vendor_carousels.dart`, `customer_home_screen.dart`'s `_buildSections()` (which iterates `VendorCategory.values`), and `category_section.dart`'s `HomeCategoryId`/`homeCategories` (the Home screen's icon row) **all switch/iterate over the fixed enum**. Migrating to Firestore-backed categories means changing `Vendor.category` from an enum to a `String` id, rewriting every one of those switch/iteration sites to instead read a `categories` collection, and — most disruptively — `category_section.dart`'s `HomeCategoryId` enum ties directly into per-category Iconify icon assets (`colorful_iconify_flutter`) that are currently compiled into the app; a Firestore-driven category would need an icon *identifier* (emoji, or a URL to an uploaded icon image) instead.

**Dependencies:** none new for text/enable-disable; if admin should upload a category icon *image* (not reuse the existing Iconify icon set), that reuses `image_picker`/`firebase_storage` — no new package.

**Security changes eventually required:** a new `categories/{categoryId}` collection, public read, `hasRole('admin')` write — same shape as the new `promotions` block.

---

## 8. Promotions / Offers

**Exists — fully implemented, keep as-is.** `AdminPromotionsScreen` (`mobile/lib/features/admin/screens/admin_promotions_screen.dart`) already has add/edit/delete, enable/disable, numeric-order field (deliberately not drag-and-drop, per earlier direction), image-or-video picker, upload, title/description/CTA. It's already linked from `AdminDashboardScreen`'s AppBar.

**Firestore:** `promotions/{promotionId}` (full admin CRUD; public read; customer side reads via `watchActivePromotions()`).

**Storage:** `promotions/{promotionId}/{fileName}` (image ≤5MB or video ≤50MB, admin-only write).

**Integration into the future dashboard:** this should become one destination in the new navigation (§16), not be rebuilt — the plan treats it as done, just needing to move from "AppBar icon" to "nav item."

**Outstanding caveat carried over from earlier work:** the `promotions` blocks in `firestore.rules`/`storage.rules` are written locally but **not deployed** — this is a prerequisite for *every* new admin feature in this plan, not just promotions, since none of them will work live until rules deploy.

---

## 9. Home Banners / Campaigns

**Determination: this is the same feature as Promotions, already merged — no separate system exists or should be built.** `PromoBannerCarousel` (`mobile/lib/features/customer/widgets/promo_banner_carousel.dart`) *is* the Home banner, and it already reads from the same `promotions` collection `AdminPromotionsScreen` manages. There is no second "campaigns" concept, hardcoded banner, or separate collection anywhere in the codebase (the old hardcoded `promoBanner1-3` l10n strings were removed when this was built). Nothing to plan here beyond what §8 already covers — building a separate "Banners" section in the nav would be pure duplication.

---

## 10. Notifications

**Exists:** Automatic, trigger-only, no admin composition. `functions/src/notifications.ts`'s `notifyUser(userId, {title, body})` is called from exactly two places in `functions/src/orders.ts` — `onOrderCreated` (notifies the vendor owner) and `onOrderStatusChanged` (notifies the customer). It reads a single `fcmToken` off `users/{userId}` and sends one FCM message; there is no batch/topic send anywhere. Client side: `push_notification_service.dart` + `features/notifications/providers/push_notification_provider.dart` keep that token fresh; `notifications_screen.dart` is the customer's own notification inbox. Note: `notifyUser` never *writes* a Firestore doc, it only sends the FCM push — there is no `notifications` Firestore collection anywhere in the schema.

**Missing:** any admin compose/broadcast UI, any "target all users" or "target a segment" concept, and any FCM **topic** infrastructure (topics would be the standard way to do "broadcast to all" cheaply instead of looping every user's token) — none of that exists in `functions/` today.

**Dependencies:** none new — `firebase_messaging`/`cloud_functions` already cover this; a broadcast would be a new `onCall` function using `messaging.sendToTopic()` (topic-subscribe would need a small client addition to `push_notification_service.dart`) or, for "selected groups," a Cloud Function that fans out `notifyUser()` calls over a queried user list.

**Security:** a new admin-broadcast callable should assert `hasRole('admin')` server-side (mirroring `assertIsDriver` in `functions/src/auth.ts`) — never a client-writable "send" trigger document, since that would let any client fire pushes to arbitrary users if the write rule were ever too loose.

---

## 11. Locations / Regions

**Exists:** `City` is a fixed 5-value Dart `enum` (`damascus, aleppo, homs, latakia, tartus`) in `mobile/lib/models/city.dart` — used as a `Vendor.city` field and as the customer's browsing preference (`selectedCityProvider`, stored **locally** in `SharedPreferences`, not Firestore).

**Missing:** everything Firestore-side — no `cities`/`regions` collection, no admin CRUD.

**Migration implications:** smaller blast radius than categories (§7) — `City` is used in fewer places: `Vendor.city`, `selectedCityProvider`, and the city-picker bottom sheet in `customer_home_screen.dart`. Same shape of change as categories: enum → Firestore-backed string id, `cityLabel()` helper in `enum_labels.dart` would need to read a name field instead of switching on the enum.

**Security:** new `cities/{cityId}` collection, public read, `hasRole('admin')` write.

---

## 12. Payments / Payouts

**Exists: nothing.** Confirmed via `pubspec.yaml` — no payment SDK (Stripe, PayPal, etc.) is a dependency. The customer Account screen's "Payment methods" menu item opens a generic `PlaceholderScreen` ("coming soon") — it is explicitly not implemented, not even a stub data model. `DeliveryOrder.total` is the only money-shaped field in the entire schema, and there's no `paidAt`/`paymentMethod`/`transactionId` anywhere.

**What would actually be needed (not inventing features, just naming the gap):** a payment provider integration (a Flutter SDK + a matching Cloud Functions webhook/callable for server-side charge confirmation) is a prerequisite *before* any admin payout screen makes sense — there is currently no money movement in this app at all, delivery is presumably cash-on-delivery implicitly. Admin "payouts to vendors/drivers" would additionally need a ledger concept (running balance per vendor/driver) that doesn't exist in any form today. This is the single largest section of the whole plan with **zero existing foundation** to build on.

---

## 13. Analytics / Reports

**Exists (partial, vendor/driver-scoped only):** `FirestoreService.countVendorOrders`, `sumVendorDeliveredSales`, `countVendorDeliveredOrders`, `countDriverDeliveries`, and `fetchRecentDeliveredOrders(vendorId, limit: 200)` (used for "most ordered items" tallying via `core/stats/menu_item_tally.dart` — the pure tally function itself is unit-tested and reusable). All of these use Firestore's native `.count()`/`.aggregate(sum(...))`, which is the right approach to extend.

**Missing:** every marketplace-wide equivalent (total revenue across all vendors, orders/day trend, popular categories across the whole marketplace, customer growth over time). None of the existing aggregation queries have a `createdAt` range filter, so "this week/month" isn't currently computable without adding one.

**Reusable pattern:** the exact same `.where(...).aggregate(sum('total'))`/`.count()` style already in `firestore_service.dart` extends cleanly to marketplace-wide versions — just without the `vendorId`/`driverId` filter, plus a `createdAt` range filter for time windows. `menu_item_tally.dart` already shows the "pure function over fetched data" pattern used for the one non-trivial report (most-ordered) that exists today.

**Security:** marketplace-wide aggregation queries need `orders` (and eventually `users`) to be readable at that scope by admin — `orders` already is (`hasRole('admin')` in the read rule); `users` is not (see §15).

---

## 14. App Settings

**Exists:** Only **device-local** preferences — `core/providers/preferences_provider.dart`'s `localeProvider`/`themeModeProvider`/`selectedCityProvider`, persisted via `shared_preferences`. None of this is admin-configurable or shared across devices/users — it's each user's own device setting, not an app-wide config.

**Missing:** any `appConfig`/`settings` Firestore document at all — there's no server-controlled flag (maintenance mode, minimum app version, delivery fee defaults, feature flags) anywhere in the schema.

**Security:** a new singleton doc, e.g. `config/appSettings`, public read (the app needs to read it on launch), `hasRole('admin')` write — same shape as `promotions`.

---

## 15. Admin Security

**Current role system:** `UserRole` enum (`customer, driver, vendor, admin`) on `AppUser.role`, stored at `users/{uid}.role`. Admin accounts are never created via the public signup form (`signup_screen.dart` doesn't offer the role) — they only come from an operator manually setting that field, out-of-band. `_RoleGate` in `mobile/lib/routing/app_router.dart` is the sole client-side dispatch point.

**Firestore rules (`firestore.rules`) admin enforcement today:**
- `hasRole(role)` helper — `get()`s the caller's own `users/{uid}.role`.
- `vendors.update`: admin may change `approvalStatus` only.
- `orders.read`: admin may read every order.
- `promotions`: admin has full write (not deployed yet — see §8).
- **Gap:** `users.read` is `isSelf(userId)` only — **admin cannot read other users' docs today**, which blocks §2/§13 entirely until this is added.
- **Gap:** `orders.update` has no admin branch at all — admin cannot write orders even though they can read them (correct today, since AdminOrdersScreen is read-only, but relevant for §5).
- **Gap:** `drivers.update` and `vendors.update` (beyond `approvalStatus`) have no admin branch.

**Storage rules (`storage.rules`) admin enforcement today:** only the `promotions/{promotionId}/{fileName}` block checks `role == 'admin'` (via an inline Firestore `get()`, since storage.rules can't import the Firestore-side `hasRole()` helper — it re-implements the same check locally). `vendorImages`/`orderProofs` have no admin path at all (by design — admin doesn't touch those today).

**Recommendation:** every future admin write should follow the *existing* pattern exactly — narrow, field-scoped `hasRole('admin')` branches added one at a time as each feature ships (never a blanket "admin can write anything"), and any operation that's race-sensitive or needs to touch Firebase Auth (not just Firestore) — user delete, role change, order cancel/reassign — should be a **Cloud Functions callable**, not a relaxed client rule, exactly matching the reasoning CLAUDE.md already documents for `acceptDelivery`/`advanceDelivery`. Never expose any of this to non-admin roles.

---

## 16. Admin Navigation — suggested structure

Today: 4 AppBar icons on one screen. Recommended eventual shape — a `Scaffold` with a `NavigationDrawer` (mobile-first, matches the rest of this app's widget choices) or a side rail on wide viewports, with one entry per section:

```
Dashboard (overview/stats)
├─ Users
├─ Vendors
│   └─ (Pending approvals badge)
├─ Drivers
├─ Orders
├─ Products
├─ Categories
├─ Promotions            ← already built, just re-hang it here
├─ Notifications
├─ Payments               (disabled/hidden until §12's foundation exists)
├─ Locations
├─ Analytics
└─ Settings
```
A shared `AdminScaffold` widget (new) wrapping this nav + an `AppBar` (title, language toggle, sign-out) would replace `AdminDashboardScreen`'s current bespoke AppBar-icon approach, and every section screen would render inside it — this is a pure UI/navigation restructuring, no data-layer risk.

---

# A. EXISTING ADMIN FEATURES
- Vendor approvals (approve/reject pending) — `admin_dashboard_screen.dart`
- All-orders viewer, read-only, status filter — `admin_orders_screen.dart`
- Promotions full CRUD + image/video upload — `admin_promotions_screen.dart`
- Role-based dashboard routing (`_RoleGate`) + rule-enforced admin writes for vendor approval, order reads, and promotions

# B. PARTIALLY IMPLEMENTED FEATURES
- Vendor management (approval only, no full CRUD/enable-disable/edit)
- Order management (view/filter only, no intervention)

# C. MISSING FEATURES
- Dashboard/overview stats
- User management (entirely — including the underlying `users.read` rule)
- Driver management
- Product management (admin side)
- Category management (+ migration off hardcoded enum)
- Notifications (admin compose/broadcast)
- Locations/regions management (+ migration off hardcoded enum)
- Payments/payouts (no foundation exists at all)
- Marketplace-wide analytics/reports
- App settings (no Firestore-backed config exists)
- Unified admin navigation shell

# D. EXISTING FIRESTORE COLLECTIONS
`users`, `vendors`, `vendors/{id}/menuItems`, `drivers`, `orders`, `reviews`, `promotions`, `users/{id}/addresses`

# E. EXISTING STORAGE PATHS
`vendorImages/{vendorId}/{fileName}`, `orderProofs/{orderId}/{fileName}`, `promotions/{promotionId}/{fileName}`

# F. EXISTING ADMIN FILES
- `mobile/lib/features/admin/screens/admin_dashboard_screen.dart`
- `mobile/lib/features/admin/screens/admin_orders_screen.dart`
- `mobile/lib/features/admin/screens/admin_promotions_screen.dart`

# G. RECOMMENDED ADMIN DASHBOARD STRUCTURE
See §16 — `AdminScaffold` (new shared shell) + `NavigationDrawer`/rail with Dashboard, Users, Vendors, Drivers, Orders, Products, Categories, Promotions, Notifications, Payments, Locations, Analytics, Settings.

# H. IMPLEMENTATION PLAN IN PHASES

**Phase 1 — Admin foundation/navigation/security**
Build `AdminScaffold` + nav shell; move Promotions/Orders behind it (no rebuild). Add the specific, narrow rule branches this phase unblocks: `users.read` admin carve-out (needed by nearly every later phase), deploy the already-written `promotions` rules. No new collections yet.

**Phase 2 — Users/vendors/drivers**
User list/search/detail (+ `createdAt`/`disabled` fields, admin-delete via a new callable). Vendor: full CRUD + enable/disable (widen the existing `approvalStatus`-only admin branch field-by-field). Driver: list/detail/enable-disable, optional approval workflow mirroring vendors.

**Phase 3 — Orders**
Richer admin order detail (reuse `OrderTrackingScreen` as a template). New `adminCancelOrder`/`adminReassignDriver` Cloud Functions callables (transaction-guarded, matching `acceptDelivery`'s pattern) — not client rules.

**Phase 4 — Products/categories**
Admin product browser (reuses `watchAllMenuItems()`, zero new reads) + owner-override edit/delist (`menuItems` rules gain an admin branch). Category migration: new `categories` collection + admin CRUD, then the larger refactor of `Vendor.category`, `enum_labels.dart`, `vendor_carousels.dart`, and `category_section.dart`'s `HomeCategoryId` to read Firestore instead of the enum.

**Phase 5 — Promotions/notifications**
Promotions: no build work, just confirm it's fully hung off the new nav (done in Phase 1). Notifications: new admin-broadcast callable using FCM topics (`sendToTopic`) for "all users," and a queried fan-out for "selected groups"; small client addition to `push_notification_service.dart` for topic subscription.

**Phase 6 — Payments/locations**
Locations: same shape as categories (Phase 4) — new `cities` collection, admin CRUD, refactor `City` enum usages. Payments: foundational work only — pick/integrate a payment SDK and design the ledger/transaction schema before any admin payout UI is meaningful; flag this phase as the one most likely to need a follow-up scoping conversation before implementation, since nothing today assumes any payment flow exists.

**Phase 7 — Analytics/settings**
Marketplace-wide aggregation queries (extend the existing `.count()`/`.aggregate(sum(...))` pattern with no vendor/driver filter + `createdAt` ranges) feeding the Phase-1 dashboard's stat cards properly. New `config/appSettings` doc + admin settings screen.

---
No files, rules, or configuration were changed in this investigation. Nothing was deployed.
