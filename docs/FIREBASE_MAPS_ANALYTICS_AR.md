# Firebase والخرائط والتحليلات — الإعداد والتشغيل

> **تحديث: الخرائط الآن بدون Google ولا بطاقة.** العرض بـ`flutter_map` وبيانات OpenStreetMap، والمسار وزمن الوصول عبر OpenRouteService من الخادم (`MAPS_PROVIDER=osm`، المفتاح `ORS_API_KEY` في `.env`، 2000 طلب مسار يوميًا مجانًا). ما يخص مفاتيح Google Maps أدناه **اختياري** ولا يلزم إلا إن عدتَ إلى Google (`MAPS_PROVIDER=google` على الخادم؛ وعرض Google في التطبيق أُزيل).
> - **البلاطات:** الافتراضي خادم OSM العام (يصلح للتطوير والاستخدام الخفيف فقط، وسياسته تمنع الحمل الكثيف). للإنتاج: `--dart-define=MAP_TILE_URL=https://.../{z}/{x}/{y}.png` لخدمة بلاطات مستضافة أو ذاتية الاستضافة، مع الإبقاء على الإسناد `© OpenStreetMap contributors`.
> - **أقل من Google:** بيانات الطرق في سوريا أضعف أحيانًا، ولا حركة مرور مباشرة (الزمن تقديري).
> - تغيير التطبيق: `MAPS_ENABLED=false` يعيد الخريطة التوضيحية (للاختبار).


مشروع Firebase: `tamredy-bb0f7` (رقم المشروع 815543110978). سُجّل فيه تطبيقا Android:

| التطبيق | Package | App ID |
|---|---|---|
| المريض | `com.tamreedy.patient` | `1:815543110978:android:70c5540d11edb000018cdb` |
| الممرض | `com.tamreedy.nurse` | `1:815543110978:android:5462fb73675b57d6018cdb` |

Google Analytics مرتبط (Property `565237983`) وفيه تدفقا بيانات للتطبيقين.

## ما يلزم منك (أسرار لا أنشئها ولا أحفظها)
1. **`google-services.json` لكل تطبيق** (Project settings ← تطبيقك ← تنزيل) إلى:
   - `apps/patient_app/android/app/google-services.json`
   - `apps/nurse_app/android/app/google-services.json`
   (مُستثنى من git). يفعّل Gradle ملحق Firebase تلقائيًا عند وجوده.
2. **حساب خدمة للإشعارات (خادم):** Project settings ← Service accounts ← Generate new private key. ضع JSON في متغير `FCM_SERVICE_ACCOUNT_JSON` (سطر واحد) للـWorker. لا يُرفع إلى git ولا يُلصق في أي دردشة.
3. **مفاتيح Google Maps** (Cloud Console ← مشروع `tamredy-bb0f7` ← تفعيل الفوترة، وهي مطلوبة للخرائط):
   - *مفتاح Android (Maps SDK for Android)*: قيّده بـPackage + بصمة SHA-1، وضعه في `apps/*/android/local.properties` كـ`MAPS_API_KEY=...`.
   - *مفتاح الخادم (Routes API)*: قيّده بعنوان IP للخادم، ويوضع في `GOOGLE_MAPS_SERVER_KEY` للـAPI.
   - فعّل: Maps SDK for Android، Routes API. (Geocoding يتم على الجهاز دون مفتاح.)
4. **Cloud Messaging API (V1)** مفعّلة افتراضيًا في المشاريع الجديدة؛ تحقق منها في Project settings ← Cloud Messaging.

## التشغيل
```powershell
flutter run --dart-define=DEMO=false --dart-define=API_BASE_URL=http://10.0.2.2:3000 `
  --dart-define=MAPS_ENABLED=true --dart-define=FCM_ENABLED=true --dart-define=ANALYTICS_ENABLED=true
```
بدون الأعلام تعمل التطبيقات كما كانت (خريطة توضيحية، لا إشعارات، لا تحليلات).

## الخرائط والتتبع (ما بُني)
- **خريطة Google بنمط علامة تمريضي** (تخفي النقاط التجارية، ألوان هادئة)، دبابيس مخصصة، خط مسار بإطار أبيض، **زر إعادة التمركز**، وملاءمة الكاميرا تلقائيًا.
- **المريض:** اختيار الموقع بأسلوب «الدبوس المركزي» مع تحويل الإحداثيات إلى عنوان عربي على الجهاز؛ تتبع الممرض بحركة سلسة بين قراءات GPS؛ **زمن الوصول والمسافة** من Google Routes (مع حركة المرور).
- **الممرض:** خريطة التوجه مع المسار وETA، بث الموقع كل ≥4 ث (ومع إشعار خدمة أمامية على Android)، وزر فتح تطبيق خرائط Google للملاحة الصوتية.
- **الخادم:** `GET /v1/requests/:id/route` و`GET /v1/nurse/assignments/:id/route`؛ المفتاح لا يغادر الخادم، والنتائج تُخزَّن 30 ث، وتتبع المريض للممرض مسموح أثناء `EN_ROUTE` فقط (كما قرار ADR-007).

## التحليلات (GA4)
**خصوصية:** لا تُرسل أسماء أو هواتف أو عناوين أو إحداثيات أو ملاحظات طبية؛ فقط معرّفات وأرقام وقيم قياسية. التجميع مشروط بـ`ANALYTICS_ENABLED` و`Analytics.setConsent(bool)` — اعرض شاشة موافقة قبل التفعيل في الإنتاج وحدّث سياسة الخصوصية.

| الحدث | متى | معاملات |
|---|---|---|
| `screen_view` | كل شاشة | الاسم |
| `login` | بعد الدخول | method, role |
| `service_selected` | اختيار خدمة | service_id |
| `request_submitted` | إرسال الطلب | service_id, value, currency=SYP |
| `nurse_assigned` | قبول ممرض | seconds_to_assign |
| `request_cancelled` | إلغاء | stage |
| `visit_completed` | اكتمال الزيارة | service_id |
| `payment_method_selected` | اختيار الدفع | method |
| `purchase` (قياسي) | تأكيد الدفع | value, currency, payment_method — **يغذي تقارير الإيرادات** |
| `rating_selected` | تقييم | stars |
| ممرض: `availability_changed`, `offer_received/accepted/declined/expired`, `visit_started`, `visit_completed` | | |

خصائص المستخدم: `app_role`. **اقتراح تسويقي في GA4:** علّم `request_submitted` و`purchase` كـ**Key events**، وأنشئ جمهورًا «طلب ولم يدفع» وآخر «عملاء متكررون»، وقمعًا: `service_selected` ← `request_submitted` ← `nurse_assigned` ← `purchase`. لقياس الاكتساب اربط الحملات بـ**Firebase Dynamic/Install Referrer** (Google Play) عند النشر.

## غير مُنجز/غير مُختبر
- لم يُنزَّل أي ملف إعداد ولا مفتاح بعد (يحتاجان موافقتك)؛ لذلك لم يُرسل إشعار ولا حدث فعلي ولم تُرسم خريطة Google حقيقية.
- iOS: أضف تطبيق iOS في Firebase + `GoogleService-Info.plist` + مفتاح Maps لـiOS + مفتاح APNs (يحتاج Mac).
- تحقق على جهاز: أذونات الموقع، إشعار الخدمة الأمامية، وصول الإشعار والتطبيق مغلق.
