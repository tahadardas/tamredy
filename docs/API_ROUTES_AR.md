# واجهات API المنفذة مبدئيًا — v0.8

كل المسارات الخاصة تتطلب `Authorization: Bearer <JWT>` مع role صالح في جدول users. الرمز لا يُولّد في التطبيق بعد؛ `seed:dev` يوفّر رموزًا محلية زائفة للتجربة.

| Method | Path | Role | العمل |
|---|---|---|---|
| GET | `/health` | عام | حالة الخادم |
| POST | `/v1/auth/login` | عام | **الوضع الحالي (`AUTH_MODE=password`)**: هاتف + كلمة مرور؛ قفل 15 د بعد 5 أخطاء |
| POST | `/v1/admin/users` | ADMIN | تسجيل مريض/ممرض يدويًا (كلمة مرور مؤقتة تُعرض مرة واحدة؛ ترخيص الممرض يدخل طابور الاعتماد ولا يُعتمد تلقائيًا) |
| GET | `/v1/admin/users` | ADMIN | قائمة الحسابات |
| POST | `/v1/admin/users/:id/status` | ADMIN | إيقاف/تفعيل (الإيقاف يلغي الجلسات ويُخرج الممرض من التوفر) |
| POST | `/v1/admin/users/:id/reset-password` | ADMIN | كلمة مرور مؤقتة جديدة + إلغاء الجلسات |
| POST/DELETE | `/v1/devices` | PATIENT / NURSE | تسجيل/حذف رمز FCM للجهاز |
| POST | `/v1/auth/otp/request` | عام (مُعطَّل ما لم `AUTH_MODE=otp`) | إرسال رمز OTP (حد 3 كل 10 دقائق لكل هاتف، صلاحية 5 دقائق) |
| POST | `/v1/auth/otp/verify` | عام | تبادل الرمز بـ access (15 د) + refresh (30 يوم)؛ 5 محاولات كحد أقصى؛ حسابات الإدارة تُرفض (`MFA_REQUIRED`) |
| POST | `/v1/auth/refresh` | عام | تدوير refresh؛ إعادة استخدام رمز قديم تلغي العائلة كلها |
| POST | `/v1/auth/logout` | عام | إلغاء عائلة الرموز |
| GET | `/v1/services` | مصادق | خدمات معتمدة ومسموحة |
| GET | `/v1/beneficiaries/mine` | PATIENT | المستفيدون المصرح بهم |
| POST | `/v1/requests` | PATIENT | إنشاء حجز بمفتاح Idempotency-Key |
| GET | `/v1/requests/mine` | PATIENT | سجل الطلبات |
| GET | `/v1/requests/:id` | PATIENT | التفاصيل |
| GET | `/v1/requests/:id/tracking` | PATIENT | خريطة الطلب وموضع الممرض فقط أثناء الطريق |
| POST | `/v1/requests/:id/cancel` | PATIENT | إلغاء ضمن الحالات المسموحة |
| PUT | `/v1/nurse/me/availability` | NURSE | تغير توفر الكادر |
| PUT | `/v1/nurse/me/location` | NURSE | إرسال GPS |
| POST | `/v1/nurse/me/heartbeat` | NURSE | التواجد الفعلي |
| GET | `/v1/nurse/me/offers` | NURSE | قائمة عروض مؤهلة بدون عنوان دقيق |
| POST | `/v1/nurse/offers/:offerId/accept` | NURSE | قبول ذري |
| POST | `/v1/nurse/offers/:offerId/decline` | NURSE | رفض العرض |
| GET | `/v1/nurse/assignments/:id` | NURSE | تفاصيل الإسناد النشط وموقع المريض |
| POST | `/v1/nurse/assignments/:id/depart` | NURSE | في الطريق |
| POST | `/v1/nurse/assignments/:id/arrive` | NURSE | وصل |
| POST | `/v1/nurse/assignments/:id/start` | NURSE | بدء الزيارة |
| POST | `/v1/nurse/assignments/:id/complete` | NURSE | إنهاء، تحرير الممرض |
| POST | `/v1/visits/:id/patient-review` | PATIENT | تقييم الزيارة |
| POST | `/v1/visits/:id/nurse-report` | NURSE | تقرير داخلي غير علني |
| GET | `/v1/wallet/status` | PATIENT | حالة المحفظة (معطّلة) |
| POST | `/v1/wallet/topups` | PATIENT | **501، غير مفعّلة** |
| POST | `/v1/pricing/quote` | PATIENT | تقدير السعر الفوري (+كود خصم اختياري) |
| POST | `/v1/promos/claim` | PATIENT | حفظ كود الشركة ليُطبَّق تلقائيًا على الطلب القادم |
| GET | `/v1/requests/:id/bill` | PATIENT | الفاتورة (المبلغ، المدة، الخصم، المحصّل، المتبقي) |
| GET | `/v1/nurse/requests/:id/bill` | NURSE | نفس الفاتورة للممرض |
| POST | `/v1/nurse/requests/:id/collect` | NURSE | تسجيل مبلغ مستلم؛ ناقص ← PARTIAL، كامل ← PAID مع الفكة |
| GET/POST/PATCH | `/v1/admin/services` | ADMIN | إدارة الخدمات والأسعار (تظهر في التطبيقات فورًا) |
| GET/POST/PATCH | `/v1/admin/promos` | ADMIN | إدارة أكواد الخصم + إحصاءات الاستخدام |
| GET | `/v1/admin/leaderboard?period=week\|month\|all` | ADMIN | الأفضل سمعة/عملًا/دخلًا للشركة |
| GET/POST | `/v1/admin/rewards` | ADMIN | تسجيل مكافآت الممرضين |
| POST | `/v1/requests/:id/tip` | PATIENT | إكرامية اختيارية (تُضاف للنقد المطلوب) |
| GET | `/v1/nurse/me/dues` | NURSE | رصيدي مع الشركة وسجل التسويات |
| GET | `/v1/referral/mine` / POST `/v1/referral/claim` | PATIENT | كودي الشخصي / إدخال كود صديق |
| GET/PUT | `/v1/admin/pricing-settings` | ADMIN | الرسوم والضريبة والإكرامية والإحالة والحماية (مفاتيح تفعيل) |
| POST/DELETE | `/v1/admin/holidays` | ADMIN | العطل الرسمية |
| POST/PATCH/DELETE | `/v1/admin/commission-tiers` | ADMIN | شرائح عمولة الممرض حسب التقييم |
| GET | `/v1/admin/dues` / POST `/v1/admin/dues/:nurseId/settle` | ADMIN | مستحقات الشركة وتسويتها |
| GET | `/v1/admin/promos/abuse` | ADMIN | مراجعة الاشتباه بإساءة الأكواد |
| GET/PUT | `/v1/admin/marketing` / `/v1/admin/marketing/:key` | ADMIN | ميزات التسويق (تفعيل + قيم مُتحقَّق منها) |
| GET/POST | `/v1/admin/marketing/packs` / `.../packs/grant` | ADMIN | منح باقة زيارات لمريض |
| GET/POST | `/v1/admin/broadcasts` (+ `/preview`) | ADMIN | إشعارات جماعية للمرضى (الموافقين)/الممرضين |
| GET/PUT | `/v1/me/marketing-consent` | PATIENT | موافقة العروض والإشعارات التسويقية |
| GET | `/v1/admin/dashboard` | ADMIN | مؤشرات العمليات |
| GET | `/v1/admin/requests` | ADMIN | الطلبات الأخيرة |
| GET | `/v1/nurse/me/summary` | NURSE | طلبات/زيارات اليوم، متوسط التقييم، نسبة الإكمال (N01) |
| GET | `/v1/nurse/me/earnings` | NURSE | تقدير مستحقات الشهر والعمولة وآخر الحركات (N06) — تقديري وليس دفتر حسابات |
| GET | `/v1/nurse/me/profile` | NURSE | حالة التحقق والوثائق والمهارات المعتمدة (N07) |
| GET | `/v1/admin/live` | ADMIN | عدادات المراقبة المباشرة وحالات المتابعة (A02) |
| GET | `/v1/admin/dashboard/extras` | ADMIN | إيراد اليوم وحجوزات 7 أيام (A01) |
| GET | `/v1/admin/nurses/summary` | ADMIN | ملخص الكوادر (A04) |
| GET | `/v1/admin/credentials/pending` | ADMIN / CLINICAL_REVIEWER | طابور اعتماد التراخيص (A05) |
| POST | `/v1/admin/credentials/:id/decision` | ADMIN / CLINICAL_REVIEWER | APPROVE / REJECT / NEEDS_INFO مع سبب، ويُسجَّل في `audit_log` ضمن نفس المعاملة |
| GET | `/v1/admin/finance/summary` | ADMIN | ملخص مالي تقديري للشهر (A06) |
| GET | `/v1/admin/finance/settlements` | ADMIN | تسويات النقد (A06) |
| GET | `/v1/admin/wallet/reconciliation` | ADMIN | معطّل حتى وجود مزود مرخّص (A07) |
| GET | `/v1/admin/reviews/summary` | ADMIN | التقييمات والبلاغات (A08) |
| GET | `/v1/admin/settings` | ADMIN | عرض سياسات البحث للقراءة فقط (A09) |

Socket.IO Namespace: `/live`، يتصل العميل بتمرير JWT في `auth.token` ويستقبل `connected` مع توجيه لإعادة مزامنة REST. الرسائل اللحظية لا تحمل إحداثيات أو بيانات مرضى حساسة، ويقتصر إرسالها على غرف المستخدمين الموثقين.

## متطلبات التنفيذ اللاحق
FCM، SMS/OTP، wallet provider، إتمام العروض الصالحة في خلفية الهاتف، شاشة الحالات الاستثنائية، وثائق Swagger/OpenAPI الفعلية تتطلب تنفيذًا وتحقيقًا إضافيًا.

## إدارة الممرضين والإعدادات (مدير؛ المراجع السريري يقرأ ويرفع)
`GET/POST /v1/admin/nurses/manage` · `GET/PATCH/DELETE /v1/admin/nurses/:id/profile` · `POST /v1/admin/nurses/:id/status` · `PUT /v1/admin/nurses/:id/skills` ·
`POST /v1/admin/nurses/:id/documents` (multipart: file,kind,title,licenseRef,expiresAt) · `GET /v1/admin/documents/:id/download` · `DELETE /v1/admin/documents/:id` ·
`GET /v1/admin/system-settings` · `PUT /v1/admin/system-settings/:company|dispatch|orders|security` · `GET /v1/admin/audit` · `GET /v1/admin/staff` · `PATCH/DELETE /v1/admin/staff/:id`

## التسجيل الذاتي (تطبيق المريض والممرض)
- المريض: `POST /v1/auth/register` (هاتف+اسم+كلمة مرور 8+)؛ يُنشأ له مستفيد ذاتي بموافقة تلقائية ويُسجَّل دخوله فورًا.
- الممرض: `POST /v1/auth/register-nurse` ثم رفع المستندات `POST /v1/nurse/me/documents` ومتابعة `GET /v1/nurse/me/onboarding`. لا يستقبل طلبات قبل اعتماد رخصته من «اعتماد التراخيص».
- حدود: 8 تسجيلات/ساعة لكل IP و200/ساعة عامة، ومفتاح لإغلاق كل باب من الإعدادات ← التسجيل الذاتي.
- تنبيه: ملكية رقم الهاتف غير مُتحقَّق منها حتى تفعيل رسائل SMS/OTP؛ راقب الحسابات الجديدة من لوحة الإدارة.
- الهجرة الجديدة: 010_self_registration.sql (تُطبَّق تلقائيًا).

## كلمة المرور الافتراضية واستعادتها
- الحساب الذي تنشئه الإدارة (ممرض/مريض) كلمته الأولى **123456** (قابلة للتعديل من الإعدادات ← الأمان). يُجبر صاحبه على تغييرها عند أول دخول، ويرفض الخادم أي طلب آخر قبل ذلك. حسابات المدراء والمراجعين تُولَّد لها كلمة عشوائية.
- استعادة كلمة المرور: زر «استعادة كلمة المرور» في صفحة الممرضين أو «كلمة مرور جديدة» في الحسابات؛ تعيد الكلمة الافتراضية وتُنهي جلسات الحساب.
- الهجرة 013_default_password.sql تُطبَّق تلقائيًا.

## طلبات انضمام الممرضين وتنظيم المستندات
- تطبيق الممرض: «ممرض جديد؟ قدّم طلب انضمام» ← 3 خطوات (البيانات، صورة الهوية، الرخصة أو شهادة المزاولة مع الإقرار القانوني). لا يُنشأ حساب؛ تظهر رسالة «بانتظار موعد المقابلة».
- لوحة الإدارة ← «طلبات الانضمام»: عرض الهوية والوثيقة، تحديد موعد المقابلة، اعتماد (يُنشئ الحساب بكلمة المرور الافتراضية ويُجبر على تغييرها) أو رفض بسبب.
- المسارات: `POST /v1/auth/nurse-applications` (عام، multipart)، `GET /v1/admin/applications`، `POST /v1/admin/applications/:id/{interview|approve|reject}`، `GET /v1/admin/application-documents/:id/download`.
- الملفات المشفّرة تُحفظ في مجلد لكل فئة داخل `uploads`: `licenses` و`practice-certificates` و`ids` و`degrees` و`photos` و`other`. اسم الملف المعروض والمُنزَّل: «اسم الممرض - رخصة.pdf». على القرص أسماء عشوائية لحماية الخصوصية.
- الهجرة 014 تُطبَّق تلقائيًا. إن وضعت nginx أمام الـAPI ارفع `client_max_body_size` إلى 20m.
