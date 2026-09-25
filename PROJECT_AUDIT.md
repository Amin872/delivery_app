# تقرير التدقيق (Phase 1 Audit) — شاشة المطعم للزبون

> تم فحص المشروع بالكامل (بدون أي تعديل على أي ملف) بما يشمل `pubspec.yaml`، الـrouting، الـtheme، الـlocalization، ملفات ARB (تحققت مباشرة: **185/185 مفتاح متطابق تمامًا** بين العربية والإنجليزية، ولا توجد أي نصوص عربية hard-coded في `features/customer/` أو `core/widgets/` — التزام كامل بـ localization بالفعل)، وبنية الـwidgets/الـmodels الحالية.

---

## أين توجد Restaurant Screen؟

المشروع يستخدم مصطلح **"Vendor" (متجر/مطعم)** في الكود بدل "Restaurant" — هذا هو المكافئ التقني لما تطلبه:

- **الشاشة الرئيسية للمطعم:** `mobile/lib/features/customer/screens/vendor_menu_screen.dart` (**548 سطر** — ملف كبير نسبيًا، تفصيل أدناه).
- **الشاشة التي تقود إليها (الصفحة الرئيسية/الفييد):** `customer_home_screen.dart` (285 سطر) — تعرض كاروسيلات منتجات أفقية، وعند الضغط على منتج تنتقل إلى `vendor_menu_screen.dart`.

---

## الملفات التي تتحكم بالتصميم حاليًا

| الملف | الدور | الحالة |
|---|---|---|
| `vendor_menu_screen.dart` | الشاشة كاملة: Header + معلومات المتجر + بانر + تبويبات + قائمة المنتجات | **معظم الـwidgets الفرعية مكتوبة كـ private classes داخل نفس الملف** (`_HeaderOverlayButton`, `_HeaderSearchBar`, `_StorePromoBanner`, بلوك المعلومات كامل inline) |
| `widgets/menu_item_card.dart` | كرت المنتج داخل القائمة | ملف منفصل بالفعل ✅ |
| `widgets/store_sticky_tabs.dart` | تبويبات الأقسام اللاصقة (sticky) | ملف منفصل بالفعل ✅ |
| `core/discovery/menu_sections.dart` | منطق تقسيم القائمة (Most Ordered + أقسام) — **pure functions مختبرة بـ unit tests**، منفصلة تمامًا عن الـUI | ملف منفصل، منطق نظيف ✅ |

**الخلاصة:** البنية جزئية فقط — بعض المكونات مستخرجة فعلًا، لكن **Header بالكامل (الأزرار الدائرية، شريط البحث، الشعار، معلومات المتجر، البانر) ما زال مكتوبًا داخل ملف الشاشة نفسه**. هذا بالضبط ما يجب معالجته وفق "Important Architecture Rule".

---

## الـwidgets الموجودة حاليًا (خاصة بشاشة المطعم)

- **Header:** `SliverAppBar` قابلة للتمدد (`stretch: true` + `BouncingScrollPhysics`) + صورة خلفية full-width مع blur/scrim، أزرار دائرية شفافة فوق الصورة (رجوع + مفضلة)، وشريط بحث بشكل pill في المنتصف (يفتح شاشة بحث منفصلة، ليس بحثًا حيًا داخل الشاشة).
- **شعار المتجر:** دائري، يتموضع في منتصف نقطة الالتقاء بين الصورة والقسم السفلي.
- **معلومات المتجر:** الاسم، التقييم (`StarRatingDisplay` من `core/widgets/`)، حالة مفتوح/مغلق (حقيقية من `isOpen` + `openTime`/`closeTime` إن وُجدا)، الحد الأدنى للطلب، رسوم التوصيل، مدة التوصيل، قسم "المزيد من المعلومات" قابل للطي.
- **بانر ترويجي:** نص عام ثابت (بدون أرقام وهمية).
- **تبويبات الأقسام:** لاصقة (sticky)، تتزامن مع موضع التمرير.
- **بطاقة المنتج داخل القائمة:** صورة + اسم + وصف + سعر + زر إضافة سريع (+) متصل مباشرة بحالة السلة.

---

## الـmodels المستخدمة

**`Vendor`** (`models/vendor.dart`): `id, ownerId, name, description, imageUrl, isOpen, approvalStatus, ratingSum/ratingCount, category (enum ثابت: بقالة/مطاعم/مخبوزات/مشروبات/صيدلية), city (enum: دمشق/حلب/حمص/اللاذقية/طرطوس ✅), deliveryFee, etaMinMinutes/etaMaxMinutes, minimumOrderAmount, openTime/closeTime`.

**`MenuItem`** (نفس الملف): `id, vendorId, name, price, imageUrl, available, description, section (نص حر يحدده صاحب المتجر), orderCount (محسوب تلقائيًا عبر Cloud Function عند اكتمال الطلب)`.

**ملاحظة مهمة إيجابية:** العملة الحالية في `formatters_provider.dart` هي **SYP (الليرة السورية)** والمدن هي مدن سورية فعلية — الـmodels **متوافقة بالفعل مع السوق السوري المطلوب**، لا حاجة لأي تعديل backend.

---

## نظام الـstate management

**Riverpod** (`flutter_riverpod: ^2.6.1`) — نمط ثابت عبر المشروع: الـServices (`FirestoreService`) كلاسات Dart عادية بدون أي اعتماد على Riverpod، والـProviders (`StreamProvider.family`, `StateNotifierProvider`) تغلفها فقط. السلة (`cartProvider`) وتفضيلات اللغة/الثيم/المدينة تُدار بنفس الطريقة. **لا حاجة لتغيير أي شيء هنا.**

---

## نظام الـlocalization و RTL/LTR

- `flutter gen-l10n` رسمي (ليس أي حل بديل) + ARB files، والعربية هي الـdefault locale الفعلي عند عدم وجود تفضيل محفوظ.
- **RTL/LTR تُدار تلقائيًا عبر `Localizations` + `locale` في `MaterialApp.router`، بدون أي `Directionality` يدوي** — هذا هو الأسلوب الصحيح تمامًا (وليس "ترجمة فوق layout إنجليزي"). تحقّق فعلي: زر الرجوع ينعكس تلقائيًا في RTL بدون أي كود إضافي بفضل خاصية `matchTextDirection` المدمجة في Material Icons، وكذلك `leading`/`title`/`actions` في AppBar.

---

## نظام الـtheme الحالي

- `AppTheme` + `AppGradients` (`core/theme/app_theme.dart`) — لون أساسي واحد (`brandColor = Color(0xFF7A1F3D)`) يتحكم بكل الواجهة عبر `ColorScheme.fromSeed` (Material 3)، قابل للتغيير من مكان واحد فعلًا ✅.
- `AppGradients.primary` مبني عمدًا على لون الـseed الثابت وليس `colorScheme.primary` — لأن Material 3 يقلب دور `primary` بين الوضع الفاتح والداكن (لون شاحب في الوضع الداكن)، والحل الحالي يحافظ على نفس درجة "الموف الغامق" الغنية في كلا الوضعين.
- **ما ينقصه:** `AppSpacing`/`AppRadius`/`AppShadows` مركزية — القيم حاليًا مبعثرة كأرقام inline (8, 12, 16, 24...) داخل كل widget بدل ثوابت موحّدة.

---

## ما هو قابل لإعادة الاستخدام مباشرة (بدون أي تعديل)

- نظام الألوان (`AppTheme`/`AppGradients`) كما هو.
- `ResponsiveCenter`, `star_rating.dart`, `skeleton_loader.dart`, `animated_async.dart`, `gradient_button.dart`, `confirm_dialog.dart` — كلها نظيفة وقابلة للاستخدام كما هي.
- منطق السلة (`cart_provider.dart`) بالكامل — لا حاجة لأي لمسة.
- `vendor_carousels.dart` / `menu_sections.dart` — منطق pure functions مختبر، يصلح أساسًا منطقيًا لإعادة تصميم بصري كامل دون المساس بالمنطق نفسه.

## ما يحتاج فعليًا للتعديل (تصميميًا/هيكليًا فقط)

1. **استخراج مكونات Header** من `vendor_menu_screen.dart` إلى ملفات منفصلة قابلة لإعادة الاستخدام.
2. **توحيد design tokens** (spacing/radius/shadows) بدل الأرقام المتكررة.
3. **الخط:** لا يوجد خط عربي مخصص حاليًا — التطبيق يعتمد على تحميل "Noto Sans" من شبكة Google Fonts وقت التشغيل على الويب، **وقد لوحظ فعليًا فشل هذا التحميل في بيئة التطوير الحالية** (`Failed to load font Noto Sans... Failed to fetch`) أثناء اختبار سابق. هذا يحتاج حلًا حقيقيًا (تفصيل أدناه).
4. **الصور:** `Image.network` مباشرة بدون أي تخزين مؤقت (cache) أو placeholder/fade-in أثناء التحميل — قد يسبب و ميضًا (flicker) وإعادة تحميل غير ضرورية.

---

## Dependencies الموجودة والقابلة للاستخدام مباشرة

`flutter_animate` (حركات)، `shimmer` (تحميل)، `flutter_spinkit` (مؤشرات تحميل)، و**Slivers المدمجة في Flutter** (مستخدمة بالفعل بنجاح: `SliverAppBar`, `SliverPersistentHeader`, `SliverMainAxisGroup`, `PageView` للكاروسيلات) — **لا حاجة لأي مكتبة carousel خارجية**.

## Dependencies إضافية مقترحة (لم يتم تثبيت أي شيء بعد)

| المكتبة | السبب | البديل الداخلي؟ |
|---|---|---|
| **`cached_network_image`** | مستقرة جدًا وصيانة نشطة، حل حقيقي لمشكلة عدم وجود تخزين مؤقت + توفر placeholder/fade-in/error widget جاهزة من الصندوق | لا يوجد — `Image.network` لا يوفر disk cache |
| **خط عربي** (اقتراحان، القرار متروك) | (أ) **تضمين الخط كـ asset محلي** في `pubspec.yaml` (الأفضل أداءً وموثوقية، خاصة أنه لوحظ فشل التحميل الشبكي فعليًا) — لا يحتاج أي package جديد. أو (ب) `google_fonts` (رسمي من فريق Flutter) إذا فُضّل التحميل الديناميكي رغم المخاطرة | يوجد بديل بدون أي package (asset محلي) — **موصى به** |

لا توجد حاجة لأي مكتبة إضافية أخرى (لا state management جديد، لا carousel خارجي، لا animation package ثقيل).

---

## خطة التنفيذ المقترحة (8 مراحل)

1. **✅ التدقيق (هذا التقرير)**
2. **أساسيات التصميم:** إنشاء `AppSpacing`/`AppRadius`/`AppShadows`، وحسم قرار الخط العربي (asset محلي موصى به) وتفعيله في `AppTheme`.
3. **إعادة الهيكلة المعمارية (بدون تغيير بصري):** استخراج مكونات Header الحالية إلى ملفات منفصلة قابلة لإعادة الاستخدام، مع الحفاظ على نفس الشكل الحالي تمامًا للتأكد من عدم كسر شيء.
4. **إعادة التصميم البصري — Header والمعلومات:** استلهام من الفيديو المرجعي (hierarchy, spacing, card design) بتصميم أصلي خاص بالتطبيق.
5. **إعادة التصميم البصري — المنتجات والأقسام:** `ProductCard`/`MenuItemCard`/تبويبات الأقسام/زر الإضافة السريع.
6. **الأداء:** دمج `cached_network_image` (إن تمت الموافقة) في كل نقاط تحميل الصور بالشاشة، والتأكد من lazy loading الصحيح.
7. **اختبار RTL/LTR والاستجابة:** فحص كامل على مقاسات مختلفة (iPhone SE إلى Pro Max) والتبديل الصحيح بين العربية والإنجليزية.
8. **التحقق النهائي:** `flutter analyze` + `flutter test` + مراجعة بصرية شاملة.
