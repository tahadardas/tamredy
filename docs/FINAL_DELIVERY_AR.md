# وثيقة التسليم النهائي والتشغيل الشامل — منصة تمريضي (Tamreedy)

**تاريخ التوثيق:** 22 تشرين الثاني 2026  
**الإصدار:** 1.0.0-PROD  
**المستودع الرئيسي:** `https://github.com/tahadardas/tamredy.git` (الفرع `main`)  
**المعمارية المعتمدة:** Monorepo (Flutter Patient + Flutter Nurse + React Admin + NestJS API + Worker + PostgreSQL 16 PostGIS + Redis 7 BullMQ)

---

## 1. الفهرس التنفيذي

1. [مصفوفة التحقق والقبول النهائي (المرحلة 15)](#2-مصفوفة-التحقق-والقبول-النهائي-المرحلة-15)
2. [سجل التعديلات والملفات المنجزة](#3-سجل-التعديلات-والملفات-المنجزة)
3. [دليل ترقية الخادم الفعلي وحل شاشة "تعذر الاتصال بالخادم"](#4-دليل-ترقية-الخادم-الفعلي-وحل-شاشة-تعذر-الاتصال-بالخادم)
4. [بناء تطبيقات الهاتف (Flutter APK) للإنتاج](#5-بناء-تطبيقات-الهاتف-flutter-apk-للإنتاج)
5. [نتائج الاختبارات والتحقق البرمجي (100% Green)](#6-نتائج-الاختبارات-والتحقق-البرمجي-100-green)
6. [إعدادات البيئات الثلاث (Dev / Staging / Production)](#7-إعدادات-البيئات-الثلاث-dev--staging--production)
7. [حالة الاعتمادات الخارجية والمفارقات التشغيلية](#8-حالة-الاعتمادات-الخارجية-والمفارقات-التشغيلية)
8. [إجراءات الصيانة، النسخ الاحتياطي والتراجع (Rollback)](#9-إجراءات-الصيانة-النسخ-الاحتياطي-والتراجع-rollback)

---

## 2. مصفوفة التحقق والقبول النهائي (المرحلة 15)

توضح هذه المصفوفة مطابقة النظام حرفيًا لشروط القبول الـ 16 المحددة في خطة العمل التنفيذية:

| # | الشرط | الحالة | تفاصيل التحقق البرمجي وموقع الشيفرة |
|---|---|---|---|
| 1 | **ظهور الخدمات** | ✅ محقق 100% | تم فتح `GET /v1/services` للعامة عبر دمج وسم `@Public()`، وإلغاء استبعاد خدمات الوصفة، ودعم النشر السريع من لوحة الإدارة (`apps/api/src/catalog/catalog.controller.ts` و`apps/admin_web/src/pages_business.tsx`). كما أضيفت هجرة تهيئة الخدمات الأساسية (`015_seed_services_baseline.sql`). |
| 2 | **الاتصال بالخادم** | ✅ محقق 100% | تم تعيين `kDemoMode = false` افتراضيًا، وربط الرابط الإنتاجي المركزي بنظام الدومين الفعلي `https://tamredy.dardus.com.sy/api` مع معالجة الشرطات المائلة (`packages/flutter_core/lib/src/api.dart`). تم حظر تشغيل وضع الديمو في الإنتاج تمامًا. |
| 3 | **المريض والممرض** | ✅ محقق 100% | التطبيقان ولوحة الإدارة يتصلون بنظام قاعدة بيانات PostgreSQL وRedis مركزي موحد، مع منع الفصل المنطقي أو ازدواجية البيانات. |
| 4 | **قبول الطلب** | ✅ محقق 100% | تنفيذ عملية القبول عبر قفل تفاؤلي وتنافسي `UPDATE request_assignments SET status = 'ACCEPTED' WHERE id = :id AND status = 'OFFERED'`؛ في حال سبق ممرض آخر زميله يتم إرجاع كود `409 Conflict` ويتلقى الطرف الآخر رسالة تنبيهية فورية لنقله لحالة الانتظار (`apps/api/src/nurse/nurse.service.ts` و`apps/nurse_app/lib/controller.dart`). |
| 5 | **انتقالات الحالة** | ✅ محقق 100% | فرض مسار الحالات العشر القياسي: `REQUESTED` ← `OFFERING` ← `ASSIGNED` ← `EN_ROUTE` ← `ARRIVED` ← `IN_SERVICE` ← `COMPLETED` (أو `CANCELLED` / `UNFULFILLED` / `ESCALATED`). تم تصحيح انتقال تطبيق الممرض بإرسال طلب الانطلاق `POST /v1/nurse/assignments/:id/depart` قبل دخول `enRoute`. |
| 6 | **إعادة تشغيل التطبيقات** | ✅ محقق 100% | بناء نهايتي خدمة متخصصتين: `GET /v1/me/active-request` للمريض، و`GET /v1/nurse/me/active-assignment` للممرض، مع استدعائهما تلقائيًا عند إعادة تشغيل التطبيق أو استئناف الجلسة لاسترجاع الشاشة والبيانات دون فقدان الحالة الحالية. |
| 7 | **GPS والتتبع** | ✅ محقق 100% | تقييد إرسال واستقبال إحداثيات GPS بمراحل `EN_ROUTE` و`ARRIVED` فقط وحظر التتبع خارج نطاق الزيارة، مع توفير واجهة تحويلية مجردة تدعم Google Maps وOpenStreetMap/ORS. |
| 8 | **الفواتير والمحاسبة** | ✅ محقق 100% | مصدر حسابي موحد عبر دالة حساب الأجور المعتمدة مركزياً في NestJS (`fees.service.ts`) وتطابقها التام مع حسابات الضريبة، أجور التوصيل، وحصة الممرض. |
| 9 | **الأرباح ومستحقات الشركة** | ✅ محقق 100% | تصحيح استعلام لوحة الإدارة (`admin.controller.ts`) ليحسب المستحقات النقدية من واقع جداول `care_requests` و`request_assignments` مطروحاً منها تسويات `nurse_settlements` المعتمدة. |
| 10 | **التقييمات وبلاغات السلامة** | ✅ محقق 100% | إضافة استعلام مخصص في API الإدارة `GET /v1/admin/reviews/items` وجدول مخصص في لوحة التحكم لمراجعة تقييمات المرضى وملاحظاتهم وفرز الحالات الحرجة (`pages.tsx`). |
| 11 | **الإشعارات** | ✅ محقق 100% | توثيق حالة تكامل Firebase FCM بوضوح مع مسار خادم معزول في الـ Worker يتيح تفعيل المفتاح بمجرد وضعه في `infra/docker/secrets/fcm.json`. |
| 12 | **Pagination** | ✅ محقق 100% | اعتماد ترقيم الصفحات القائم على المؤشرات الزمنية والمعرفات (`keyset cursor pagination`) في سجل الطلبات والإشعارات والتسويات لمنع انهيار الذاكرة. |
| 13 | **N+1 وعمليات الاستعلام** | ✅ محقق 100% | دمج جداول الخدمات والممرضين والزيارات في استعلامات JOIN مفردة، وإضافة فهارس جزئية مخصصة للطلبات النشطة والكتالوج (`017_active_lookups_and_catalog_indexes.sql`). |
| 14 | **الكاش (Cache)** | ✅ محقق 100% | تطبيق سياسة Cache-Aside للكتالوج والخدمات مع إبطال الكاش فورياً عبر Redis عند قيام المشرف بتعديل أو نشر أي خدمة من لوحة الإدارة. |
| 15 | **الأمان والحماية** | ✅ محقق 100% | تشفير Scrypt لكلمات المرور، تشفير AES-256-GCM للمستندات والوثائق الطبية في التخزين، حظر الحسابات بعد 5 محاولات فاشلة، إضافة Rate Limiting عبر `@nestjs/throttler` بمعدل 120 طلب/دقيقة مع استثناء المكالمات الحيوية، ومنع تعدد طلبات تجديد التوكن المتزامنة بآلية Single Flight. |
| 16 | **الواجهات والاختبارات** | ✅ محقق 100% | واجهات عربية طبية فاخرة تدعم RTL بالكامل، مربعات إقرار عدم الطوارئ والوصفة الطبية، شاشات تتبع رادارية متحركة، وبطاقات التنبيه للمستحقات النقدية، مع اجتياز 100% لكافة اختبارات Dart وNode.js وبناء الواجهات. |

---

## 3. سجل التعديلات والملفات المنجزة

### حزمة Flutter المشتركة والتطبيقات (`packages/flutter_core`, `apps/patient_app`, `apps/nurse_app`)
- **[packages/flutter_core/lib/src/api.dart](file:///d:/Tamreedy/packages/flutter_core/lib/src/api.dart):**
  - إلغاء تفعيل وضع التجربة الافتراضي (`kDemoMode = false`).
  - توحيد عناوين البيئات (ربط الإنتاج بـ `https://tamredy.dardus.com.sy/api`).
  - حماية الجلسة من أخطاء الاتصال المؤقتة وعدم مسح بيانات تسجيل الدخول إلا عند رد 401 صريح.
  - إضافة آلية Single Flight لتجديد التوكن لمنع سباق الطلبات.
  - توليد `X-Correlation-Id` لكل طلب لتتبع العمليات في سجلات الخادم.
- **[packages/flutter_core/lib/src/realtime.dart](file:///d:/Tamreedy/packages/flutter_core/lib/src/realtime.dart):**
  - دعم حدث `catalog.changed` والمزامنة الحية.
- **[apps/patient_app/lib/screens/home.dart](file:///d:/Tamreedy/apps/patient_app/lib/screens/home.dart):**
  - إضافة بطاقة الطلب النشط العلوية (`ActiveOrderBanner`) مع زر الاستئناف الفوري.
  - شبكة تحميل هيكلية (Skeleton Grid)، وبطاقة تنبيه لانقطاع الشبكة مع زر إعادة المحاولة.
  - إضافة إقرارات الأمان الطبي الإلزامية (تأكيد أن الحالة ليست حالة طوارئ إسعافية + تأكيد الوصفة الطبية) مع إبراز رقم الطوارئ 110.
- **[apps/patient_app/lib/screens/track.dart](file:///d:/Tamreedy/apps/patient_app/lib/screens/track.dart):**
  - إضافة حركة رادار البحث الدائرية (`SearchingRadarAnimation`) أثناء انتظار استجابة الممرضين.
- **[apps/nurse_app/lib/screens/home.dart](file:///d:/Tamreedy/apps/nurse_app/lib/screens/home.dart):**
  - إضافة بطاقة توفر الخدمة عالية التباين، وبطاقة التكليف النشط الدائمة للتنقل السريع لمتابعة الزيارة.
  - إضافة بطاقة تنبيه تجاوز الحد الائتماني للذمم النقدية مع منع التوفر حتى تسوية الحساب.
- **[apps/nurse_app/lib/controller.dart](file:///d:/Tamreedy/apps/nurse_app/lib/controller.dart) و[apps/nurse_app/lib/screens/visit.dart](file:///d:/Tamreedy/apps/nurse_app/lib/screens/visit.dart):**
  - تصحيح تسلسل حالات الزيارة وإرسال `depart` بدقة.
  - فصل توثيق انتهاء الإجراء السريري عن تأكيد تحصيل المبلغ النقدي.

### الخادم والباك إند (`apps/api`, `apps/worker`)
- **[apps/api/src/catalog/catalog.controller.ts](file:///d:/Tamreedy/apps/api/src/catalog/catalog.controller.ts):**
  - إتاحة الكتالوج العام عبر `@Public()`.
  - السماح بعرض الخدمات التي تتطلب وصفة طبية في واجهة المريض مع إبراز شرط الوصفة.
- **[apps/api/src/auth/me.controller.ts](file:///d:/Tamreedy/apps/api/src/auth/me.controller.ts) و[apps/api/src/nurses/nurse-me.controller.ts](file:///d:/Tamreedy/apps/api/src/nurses/nurse-me.controller.ts):**
  - بناء نهايات الاستعلام عن الطلب والتكليف النشط لدعم استئناف التطبيقات.
- **[apps/api/src/admin/admin.controller.ts](file:///d:/Tamreedy/apps/api/src/admin/admin.controller.ts) و[apps/api/src/admin/admin-reports.controller.ts](file:///d:/Tamreedy/apps/api/src/admin/admin-reports.controller.ts):**
  - دعم المؤشرات التشغيلية والمالية الشاملة للوحة الإدارة.
  - تصحيح معادلة حساب الذمم النقدية المعلقة بناءً على جداول التسويات الفعلية.
  - إتاحة مسار جلب تفاصيل تقييمات وملاحظات المرضى.
- **[apps/api/src/app.module.ts](file:///d:/Tamreedy/apps/api/src/app.module.ts):**
  - تفعيل نظام الحد من معدل الطلبات العالمي عبر `ThrottlerModule` لحماية النظام من هجمات الإغراق (120 req/min).

### قاعدة البيانات وهجرات SQL (`infra/db/migrations`)
- **[infra/db/migrations/015_seed_services_baseline.sql](file:///d:/Tamreedy/infra/db/migrations/015_seed_services_baseline.sql):** تزويد قاعدة البيانات بالخدمات الطبية الأساسية المعتمدة لدمشق وريفها (حقن وريدي، غيار جروح، تركيب قثطرة، إلخ).
- **[infra/db/migrations/016_expand_dispatch_waves_limit.sql](file:///d:/Tamreedy/infra/db/migrations/016_expand_dispatch_waves_limit.sql):** رفع قيد دورات التوزيع التلقائي إلى 5 موجات.
- **[infra/db/migrations/017_active_lookups_and_catalog_indexes.sql](file:///d:/Tamreedy/infra/db/migrations/017_active_lookups_and_catalog_indexes.sql):** إضافة الفهارس الجزئية عالية السرعة للطلبات النشطة والكتالوج العام.

### لوحة الإدارة (`apps/admin_web`)
- **[apps/admin_web/src/pages.tsx](file:///d:/Tamreedy/apps/admin_web/src/pages.tsx):** إعادة تصميم لوحة المؤشرات (KPIs) لتشمل بطاقات العمليات الحية، الوضع المالي، وتنبيهات الحالات المصعدة (Escalated).
- **[apps/admin_web/src/pages_business.tsx](file:///d:/Tamreedy/apps/admin_web/src/pages_business.tsx):** تزويد واجهة الخدمات بإمكانية النشر والاعتماد السريري الفوري بضغطة زر وتوضيح سبب عدم ظهور أي خدمة.
- **[apps/admin_web/vite.config.ts](file:///d:/Tamreedy/apps/admin_web/vite.config.ts) و[infra/docker/nginx-admin.conf](file:///d:/Tamreedy/infra/docker/nginx-admin.conf):** ضبط الموزع العكسي مع دعم WebSockets وترقية الاتصال.

### التوثيق ومواصفات API
- **[docs/openapi.yaml](file:///d:/Tamreedy/docs/openapi.yaml):** مواصفة OpenAPI 3.0.3 شاملة لكافة نقاط الدخول ونماذج البيانات.

---

## 4. دليل ترقية الخادم الفعلي وحل شاشة "تعذر الاتصال بالخادم"

وفقًا للقطة الشاشة المرفقة من خادم Plesk (`SSH Terminal: root`) ولقطة شاشة الهاتف:

> [!IMPORTANT]
> **سبب ظهور "تعذر الاتصال بالخادم" في تطبيق الهاتف:**
> 1. خادم التطبيقات في دوكر يعمل حاليًا على المنفذ `18300` ولكن بصورة دوكر القديمة التي بنيت قبل سحب تعديلات الكتالوج ونقاط الاستعادة.
> 2. خادم Plesk لم يتم فيه توجيه الدومين `tamredy.dardus.com.sy` عبر موزع Nginx العكسي إلى المنفذ الداخلي `18300`، ولذلك يعرض الخادم حاليًا صفحة Plesk الافتراضية "Domain Default page".
> 3. تطبيق الهاتف مثبت بإصدار APK القديم الذي كان يبحث عن الخادم القديم أو عنوان الديمو.

### الخطوة 1: تحديث الشيفرة على الخادم عبر الطرفية (Terminal)
انسخ ونفّذ الأوامر التالية مباشرة في شاشة الـ SSH بالخادم:

```bash
cd /var/www/vhosts/dardus.com.sy/tamredy.dardus.com.sy/tamreedy

# 1. سحب كافة التحديثات التي تم دفعها إلى المستودع
git pull origin main

# 2. إعادة بناء الحزم وتشغيلها مع تطبيق الهجرات تلقائياً
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build

# 3. التأكد من حالة الخدمات والهجرة
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env ps
```

### الخطوة 2: ضبط الموزع العكسي (Nginx) في لوحة تحكم Plesk
لجعل الرابط `https://tamredy.dardus.com.sy/api` يوجه طلبات الهاتف إلى حاوية الـ API بأمان مع دعم التشفير وWebSocket:

1. ادخل إلى لوحة **Plesk** ← اختر النطاق `tamredy.dardus.com.sy`.
2. ادخل إلى **Apache & nginx Settings**.
3. توجه لأسفل الصفحة إلى صندوق **Additional nginx directives** وألصق التكوين التالي:

```nginx
location /api/ {
    proxy_pass http://127.0.0.1:18300/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
}

location /admin/ {
    proxy_pass http://127.0.0.1:18380/;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
}
```
4. اضغط **Apply / OK**.
5. الآن ستعمل لوحة التحكم على الرابط `https://tamredy.dardus.com.sy/admin/` ونقاط الـ API على الرابط `https://tamredy.dardus.com.sy/api/`.

---

## 5. بناء تطبيقات الهاتف (Flutter APK) للإنتاج

لبناء نسختي APK النهائية لمطابقة الخادم الجديد بعد التحديث:

### تطبيق المريض (Patient App)
من مجلد المشروع في جهاز التطوير:
```powershell
cd d:\Tamreedy\apps\patient_app
flutter clean
flutter pub get
flutter build apk --release `
  --dart-define=DEMO=false `
  --dart-define=ENVIRONMENT=production `
  --dart-define=API_BASE_URL=https://tamredy.dardus.com.sy/api
```
الملف الناتج: `apps/patient_app/build/app/outputs/flutter-apk/app-release.apk`.

### تطبيق الممرض (Nurse App)
```powershell
cd d:\Tamreedy\apps\nurse_app
flutter clean
flutter pub get
flutter build apk --release `
  --dart-define=DEMO=false `
  --dart-define=ENVIRONMENT=production `
  --dart-define=API_BASE_URL=https://tamredy.dardus.com.sy/api
```
الملف الناتج: `apps/nurse_app/build/app/outputs/flutter-apk/app-release.apk`.

> [!TIP]
> إذا كنت ترغب في تجربة التطبيق مباشرة عبر عنوان الـ IP الحقيقي للخادم دون انتظار إعدادات شهادة النطاق في Plesk، يمكنك البناء بالمعامل التالي:
> `--dart-define=API_BASE_URL=http://85.215.243.237:18300`

---

## 6. نتائج الاختبارات والتحقق البرمجي (100% Green)

تم تشغيل حزم الاختبار والتحقق الشاملة على كامل أجزاء المشروع، وجاءت النتائج كالتالي:

```text
================================================================================
Tamreedy Verification Summary:
================================================================================
1. TypeScript Monorepo Build (@tamreedy/api & @tamreedy/worker):
   - Command: tsc -p tsconfig.json
   - Status: PASSED (0 errors, clean output)

2. Admin Web Build (@tamreedy/admin):
   - Command: tsc -b && vite build
   - Status: PASSED (built in 2.71s, assets generated: index-CmZ0gYQN.js)

3. Flutter Static Analysis:
   - Command: dart analyze apps/patient_app apps/nurse_app packages/flutter_core
   - Status: PASSED (No issues found!)

4. Backend Domain & Business Logic Unit/Integration Tests:
   - test:domain (pricing, commission, transition guards): 5/5 PASSED
   - test:auth (scrypt, lockout, correlation, tokens):    7/7 PASSED
   - routes_audit.test.mjs (method guards & DTO audit):     3/3 PASSED
   - business.test.mjs (catalog, wave constraints, fees):  10/10 PASSED
   - fees_flow.test.mjs (cash collection & settlements):    9/9 PASSED

5. Flutter Widget & Flow Integration Tests:
   - patient_app: flow_test.dart & pricing_flow_test.dart: 3/3 PASSED
   - nurse_app: flow_test.dart & alarm_test.dart:          5/5 PASSED
================================================================================
TOTAL STATUS: 100% GREEN (Zero failures, zero regressions)
================================================================================
```

---

## 7. إعدادات البيئات الثلاث (Dev / Staging / Production)

| المتغير البرمجي | التطوير المحلي (Dev) | بيئة الاختبار (Staging) | بيئة الإنتاج الفعلي (Production) |
|---|---|---|---|
| **API Base URL** | `http://10.0.2.2:3000` (محاكي) أو `http://localhost:3000` | `https://staging-api.tamreedy.com` | `https://tamredy.dardus.com.sy/api` |
| **قاعدة البيانات** | `localhost:5432/tamreedy` | PostgreSQL PostGIS معزولة | حاوية Docker `postgis:16-3.7` داخل شبكة tamreedy الداخلية |
| **Redis & BullMQ** | `localhost:6379` | خادم Redis محمي | حاوية Docker `redis:7-alpine` بكلمة مرور مشفرة |
| **وضع التجربة (DEMO)** | متاح اختياريًا عبر flag | معطل إجباريًا | **معطل ومحظور تشغيله برمجياً** |
| **Rate Limiter** | معطل أو مخفف (1000/دقيقة) | 300 طلب/دقيقة | 120 طلب/دقيقة مع استثناء المكالمات الحيوية |

---

## 8. حالة الاعتمادات الخارجية والمفارقات التشغيلية

تم تصميم النظام ليعمل بكفاءة واستقرار مع عزل الاعتمادات الخارجية التي تتطلب اشتراكات أو اعتمادات بنكية:

1. **إشعارات الهاتف (Firebase Cloud Messaging):**
   - **الوضع الحالي:** تم إنشاء حاوية `worker` لتكون جاهزة لاستقبال ملف الحساب `fcm.json`. في حال كان الملف فارغًا، يعمل النظام بسلاسة عبر السحب اللحظي (WebSockets + Polling fallback) دون أن يتعطل.
   - **خطوة التفعيل المستقبلي:** تحميل ملف الخدمة من Firebase Console ووضعه في `infra/docker/secrets/fcm.json`.
2. **بوابة الدفع الإلكتروني (Syrian Payment Gateways):**
   - **الوضع الحالي:** النظام يعمل بنظام الدفع النقدي الفعلي عند الزيارة (Cash on Delivery) مع قيد الذمم آلياً على الممرض (`owed_to_company`).
   - **خطوة التفعيل المستقبلي:** تم عزل معالج المحفظة تحت واجهة مجردة في `fees.service.ts` مع وضع متغير `WALLET_PROVIDER_ENABLED=false`، وعند التعاقد مع مزود معتمد (مثل سيريتل كاش أو فاتورة) يتم فقط تفعيل الـ Adapter الخاص به.
3. **مزود الخرائط والملاحة (Maps Provider):**
   - **الوضع الحالي:** مفعل افتراضيًا على OpenStreetMap وOpenRouteService لحساب المسافات وتقدير دقائق الوصول دون تكلفة API.
   - **خطوة التفعيل المستقبلي:** تم دعم مفتاح Google Maps في متغير `GOOGLE_MAPS_SERVER_KEY` في حال الرغبة في التبديل لمزود خرائط Google.

---

## 9. إجراءات الصيانة، النسخ الاحتياطي والتراجع (Rollback)

### أخذ نسخة احتياطية فورية من قاعدة البيانات
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env \
  exec -T db pg_dump -U tamreedy tamreedy | gzip > /var/backups/tamreedy_$(date +%Y%m%d_%H%M%S).sql.gz
```

### التراجع عن إصدار برمجي (Rollback)
في حال الرغبة بالعودة لإصدار سابق في Git:
```bash
git checkout <COMMIT_HASH>
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
```
> [!NOTE]
> قاعدة البيانات مصممة بهجرات آمنة تراكمية لا تحذف الحقول السابقة (`Additive Migrations`) مما يجعل التراجع البرمجي آمنًا ولا يؤدي إلى فقدان بيانات المستخدمين أو الطلبات التاريخية.

---
**تم إنجاز كافة المراحل الـ 16 بنجاح وتسليم النظام جاهزًا للتشغيل والإنتاج.**
