# تمريضي — Tamreedy | المرحلة البرمجية الأولى (v0.2 — Performance)

**هذه حزمة شيفرة مصدرية حقيقية للمرحلة التأسيسية، وليست نظامًا طبيًا جاهزًا للإنتاج.** مرفق معها تصاميم ومرجع SRS v1.0 المعتمدة. لا تُحمّل إليها بيانات مرضى فعلية، ولا تنشرها على الإنترنت قبل استكمال الهوية والترخيص والتدقيق الأمني والسريري.

## تحديث الأداء v0.2 — 21 نوفمبر 2026

هذه النسخة **تبني على v0.1 ولا تستبدل محرك قبول الطلبات**. أهم ما أضيف فعليًا:

- ترحيل SQL جديد `infra/db/migrations/002_query_indexes.sql` لفهرسة مفاتيح FK وقراءات التصفح والتوزيع الجغرافي، من غير فهرسة PK/UNIQUE مرتين.
- قوائم المرضى والإدارة وتاريخ الممرض بـ **Keyset/Cursor Pagination** (`limit` الافتراضي 20 والأقصى 50)، مع مؤشر صفحة موقَّع خاص بالمستخدم/الفلاتر ودقة توقيت ميكروثانية.
- إزالة SQL per-nurse من `apps/worker/src/main.ts` وتحويل إنشاء العروض وإشعارات Outbox إلى CTE جماعي.
- Cache-aside لخدمات الكتالوج العامة في Redis بمدة 300 ثانية، مع تحديث إصدار الكاش عند تعديل ظهور خدمة، وإبطال موزع عبر outbox. **الأذونات والمال والمواقع والممرضون النشطون غير مخزنين في هذا الكاش.**
- لوحة الإدارة أصبحت تدعم زر تحميل المزيد بدل الاقتصار على 100 طلب؛ وأُزيل التحديث الدوري كل 15 ثانية.
- اختبارات الأداء والمنطق: **12/12 ناجحة** في بيئة إنشاء الحزمة (اختبارات وحدات وفحوص شيفرة)، و13 ملف TypeScript/TSX مترجم صياغيًا دون أخطاء. **لم تُشغل اختبارات PostgreSQL/Redis ولا اختبارات P95 أو البناء النهائي بسبب غياب الاعتمادات والخدمات في البيئة.**

التوثيق التنفيذي: `docs/performance/PERFORMANCE_GUIDE_AR.md`، ومراجعة الفهارس وخطة الاستعلامات: `apps/api/scripts/audit-query-plans.mjs`.

⚠️ **تغيير عقد API:** نهايات `GET /v1/requests/mine` و`GET /v1/admin/requests` تعيد `{items,hasMore,nextCursor}` بدل مصفوفة مباشرة. يجب تحديث أي مستهلك قديم لها. واجهة إدارة الطلبات الحالية محدثة لهذا العقد.

```bash
# من جذر المشروع بعد تثبيت pnpm deps وتشغيل PostgreSQL وRedis:
pnpm db:migrate
pnpm test:performance
# على قاعدة اختبار منفصلة:
TEST_DATABASE_URL=postgres://... AUDIT_USER_ID=<uuid> pnpm audit:query-plans
```

## ما تم تنفيذه فعليًا

- خادم Node.js/TypeScript بأسلوب NestJS، وقاعدة PostgreSQL/PostGIS، وmigrations، وإعداد Docker Compose محلي.
- إنشاء الطلب مع `Idempotency-Key` وسجل الأحداث، والعروض الجغرافية على موجات 3/6/10 كم في Worker.
- قبول ذري لأول ممرض مؤهل ضمن Transaction مع صفوف مقفلة وقيود فريدة مزدوجة في قاعدة البيانات.
- إسناد الطلب وإيقاف استقبال الممرض لطلبات أخرى، وحالات depart/arrive/start/complete، وإعادة توفره بعد الإنهاء عند استيفاء الشروط.
- APIs لتسجيل توفر الممرض وتحديث موقعه وقائمة عروضه وعنوان الزيارة بعد قبولها فقط.
- تتبع موقع الممرض للمريض أثناء `EN_ROUTE` فقط عبر API مصرح به، مع إشعارات WebSocket/Redis لتحديثات الحالة.
- واجهتان تأسيسيتان Flutter/Dart؛ إحداهما للمريض والأخرى للممرض، وخريطة Google ضمن واجهة المريض وواجهة الزيارة للممرض.
- لوحة إدارة React/TypeScript/RTL تتصل بلوحة الإحصاءات والطلبات بحساب إداري، وبقية الأقسام ظاهرة كصفحات تأسيسية غير مكتملة.
- تقييم المريض بعد الزيارة وتقرير داخلي من الممرض؛ محرك المحفظة غير مفعل قانونيًا وماليًا.
- اختبار Domain يعمل من المصدر الفعلي دون تثبيت الحزم، واختبار SQL تكاملي اختياري يحتاج قاعدة Test منفصلة.

## ما لم يكتمل **ولا يجوز تقديمه على أنه جاهز**

1. تسجيل دخول SMS/OTP حقيقي، إصدار JWT عبر خدمة معتمدة، إعادة تعيين الجلسات، MFA للإدارة، سياسات RBAC تفصيلية.
2. تحقق وثائق الممرضين والإشراف السريري الكامل؛ لا يوجد أي تأهيل طبي معتمد داخل هذه الحزمة.
3. ربط FCM، تتبع خلفي مستمر مع أذونات Android/iOS، وإعادة اتصال Socket.IO كاملة على الهواتف.
4. التسويات المحاسبية المتوازنة، الدفع المختلط، محفظة فعلية/مزود مرخص، تأكيد قبض النقد والفكة.
5. واجهات تطبيقات Flutter الـ27 كما في التصاميم المرجعية؛ الحالي أساس تنفيذي قابل للتمديد وليس مطابقة بصرية كاملة.
6. إدارة الحوادث/إلغاء الإسناد بواسطة الممرض وإعادة التوزيع وإشعارات فقدان الاتصال المتقدمة.
7. اختبارات API/Flutter التكاملية، اختبارات FCM وخرائط فعلية، اختبارات حمل حقيقية، اختبارات أمنية، تطبيقات مثبتة وموقعة، وخطة نشر إنتاجية.
8. نظام مصادقة مستخدم وإدارة موافقات شامل؛ البيانات التجريبية المحلية لا تصلح لأي ممارسة تمريضية.

## البنية

```text
Tamreedy_Phase1_Source/
├── apps/
│   ├── patient_app/           # Flutter + Dart، نسخة مبدئية
│   ├── nurse_app/             # Flutter + Dart، نسخة مبدئية
│   ├── admin_web/             # React + TypeScript + Vite
│   ├── api/                   # NestJS 12 + TypeScript
│   └── worker/                # Node.js + pg + Redis
├── packages/
│   ├── flutter_core/          # Theme + Dio + Secure Storage
│   └── design_system/         # Color tokens
├── infra/
│   ├── db/migrations/         # PostgreSQL + PostGIS DDL
│   └── docker/                # Docker Compose (DEV ONLY)
├── reference_design/         # الشعار و27 شاشة وأطلس التصميم من SRS
├── docs/                     # API، الأمن، تنفيذ المرحلة التالية
└── .env.example
```

## متطلبات أدوات التطوير

- Node.js 26 LTS، و`pnpm` 10، وPostgreSQL/PostGIS عبر Docker، وFlutter 3.50 + Android SDK؛ الإصدارات المعتمدة من وثيقة SRS.
- حزم NestJS مثبتة بإعدادات semver في `package.json` ويجب تدقيق التوافق وتوليد ملف قفل `pnpm-lock.yaml` في بيئة متصلة بـnpm registry قبل البناء الإنتاجي.
- Google Maps Android/iOS API keys من حساب مالك المشروع؛ لا توجد مفاتيح أو بيانات مستخدم حقيقية.

## تشغيل بيئة التطوير المحلية

```bash
cd infra/docker
# Docker Desktop / Docker Engine ضروري. لا تنشر هذه المنافذ على خادم عام.
docker compose up -d
cd ../..
cp .env.example .env
# عدّل JWT_SECRET إلى قيمة عشوائية لا تقل عن 32 حرفًا وحدّث DATABASE_URL
corepack enable
pnpm install
export $(grep -v '^#' .env | xargs)  # Linux dev shell only; لا تستخدمه مع أسرار متعددة الأسطر
pnpm db:migrate
NODE_ENV=development pnpm --filter @tamreedy/api seed:dev
pnpm dev:api
# شغّل Worker في نافذة مستقلة
pnpm dev:worker
# ولوحة الإدارة:
pnpm dev:admin
```

**تضارب إعدادات كلمة مرور PostgreSQL:** `docker-compose.yml` يستخدم افتراضيًا `dev_change_me` و`.env.example` كذلك في التنمية المحلية فقط؛ غيّر القيم معًا قبل أي استخدام على شبكة مشتركة، ولا تنشر كلمة مرور المثال.

`seed:dev` يعمل على `localhost` حصريًا وفي `NODE_ENV=development` ويولّد مستخدمين افتراضيين وتوكنات قصيرة العمر، وخدمة **محاكاة غير طبية فقط**. لا تستخدم السجلات التجريبية أو أرقام الهواتف الوهمية في الإنتاج.

## إنشاء مشاريع Flutter الأصلية

لا تتوفر أدوات Flutter في بيئة إنشاء هذه الحزمة؛ توجد ملفات Dart و`pubspec.yaml` فقط، ولم تُنشأ مشاريع Android/iOS الأصلية. نفّذ على جهازك (داخل مسار كل تطبيق)، واحفظ الملفات الحالية قبل توليد قوالب المنصة:

```bash
cd apps/patient_app
flutter create --platforms=android,ios --project-name tamreedy_patient_app .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=DEV_DEMO=true --dart-define=DEV_TOKEN=YOUR_LOCAL_DEVELOPMENT_PATIENT_TOKEN

cd ../nurse_app
flutter create --platforms=android,ios --project-name tamreedy_nurse_app .
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000 --dart-define=DEV_DEMO=true --dart-define=DEV_TOKEN=YOUR_LOCAL_DEVELOPMENT_NURSE_TOKEN
```

لأجهزة iOS يلزم Mac وXcode؛ وقد تتطلب مسارات Android/iOS أذونات موقع وتهيئة Gradle وAPI keys طبقًا لتعليمات الحزم. رمز `DEV_TOKEN` للتطوير المحلي فقط ولا يجوز تمريره في نسخ إصدار عامة.

## اختبارات تم تنفيذها هنا

```
node --test apps/api/tests/domain.test.mjs
```

تُترجم الاختبارات ملف `states.ts` الفعلي ثم تتحقق من دورة الحالات وتدرج البحث والحساب النقدي الدقيق. اختبارات التزامن الحقيقية تتطلب تثبيت `pg` وقاعدة PostgreSQL منفصلة بإعداد `TEST_DATABASE_URL`؛ **لم يتم تشغيلها في بيئة إعداد الأرشيف**.

## الأمان والترخيص

- لا يوجد أي Wallet API فعّال للشحن أو حفظ أموال المستخدمين. Endpoint المحفظة يعيد `501` للشحن.
- اعتمد ترخيص منصة الخدمات الصحية والعقود الطبية والتحقق من مزاولات المهنة قبل خدمة المرضى.
- لا تسمح للعميل بقبول الحالات الإسعافية بوصفها طلبات عادية، وافصل إشراف حالات التمريض الطبي عن الرعاية غير الطبية.
- كل API حساس يفترض JWT مستخدمًا من مصدر خارجي آمن؛ الجلسات وإصدار التوكن الحقيقي ضمن المرحلة التالية.
- راجع `docs/SECURITY_AND_GAPS_AR.md` قبل الإنتاج.
