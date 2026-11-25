# دليل API لتمريضي لمودل التصميم

يتضمن **283 عملية HTTP** مسجّلة في تطبيق السيرفر. الوظائف والأدوار مبنية على النسخة المحلية من الكود. إتاحة كل وظيفة على الإنتاج تعتمد على النسخة المنشورة وإعدادات الميزات.

## تعليمات جاهزة لمودل التصميم

- صمّم واجهات منفصلة للمريض والممرض والإدارة. اربط كل إجراء بمساره المحدد هنا. عند وصف الدور بـ«حسب الصلاحية»، تحقّق من الـController قبل عرض الإجراء؛ الأدوار وحدها لا تمنح حق قراءة طلب أو سجل لا يخص المستخدم.
- اجعل عنوان API متغير إعدادات واحدًا. تسبق المسارات المحمية ترويسة `Authorization: Bearer <accessToken>`. أرسل JSON للعمليات المعتادة و`multipart/form-data` للرفع حيث يظهر في الجدول.
- صمّم حالات التحميل والفراغ ونجاح الإجراء وفشله. استخدم `code` عند إرجاعه، وتعامل مع 401 لانتهاء الجلسة، و403 للصلاحيات، و404 للسجل، و409 لتغير الحالة، و429 لكثرة المحاولات. امنع الضغط المتكرر أثناء عمليات الكتابة.
- اعرض العربية باتجاه RTL مع تنسيق المواعيد بتوقيت دمشق. أرسل التوقيت المطلق بصيغة ISO 8601 مع المنطقة الزمنية. أبقِ معرّفات الطلبات وبيانات الدخول خارج الشاشات العامة.
- اقرأ إتاحة الميزات من API. على سبيل المثال، شحن المحفظة مسجّل لكنه يعيد 501، ورمز OTP يتبع وضع المصادقة. الرفع والتنزيل المحميان يحتاجان الجلسة نفسها.

## مسارات تصميم أساسية

**طلب زيارة** · الفئات والخدمات ← تقدير السعر ← اختيار المستفيد والعنوان والإحداثيات ← إنشاء الطلب بمفتاح `Idempotency-Key` ثابت للمحاولة نفسها ← تفاصيل الطلب والتتبّع. اعرض الإلغاء حسب سياسة الإلغاء وحالة الطلب.

**السوق المفتوح** · الممرض يقرأ `GET /v1/marketplace/requests` ويرسل `POST /v1/marketplace/requests/:id/proposals`. جسم الطلب مثالًا `{"arrivalMinutes":20,"note":"جاهز للزيارة"}`. يلزم `arrivalMinutes` من 5 إلى 1440 أو `proposedArrivalAt`، والملاحظة اختيارية بحد 300 حرف. وقت الوصول تقديري والسعر يحدده السيرفر. يرى المريض العروض عبر `GET /v1/requests/:id/proposals`، ثم يقبل أو يرفض. قبول المريض هو الذي يُسند الطلب.

**الزيارة الميدانية** · الإسناد ← الانطلاق ← الوصول ← بدء الخدمة ← الإكمال ← الفاتورة والتحصيل عند توفرها. كل انتقال له عملية مستقلة وحالة مؤكدة من السيرفر.

**الزيارات المجدولة للإدارة** · قائمة الزيارات وخطط الرعاية ← تفاصيل سجل الزيارة. اعرض الممرض المكلّف والوصول المسجل في حقول منفصلة. عملية إزالة الموعد تؤرشفه، وقد تلغيه أولًا إذا كان لا يزال مجدولًا بلا إسناد.

**التحديث اللحظي** · Socket.IO على `/live` مع `auth.token`. حدث `connected` يطلب مزامنة عبر REST. أمثلة أحداث العميل `catalog.changed` و`offer.created` و`request.assigned` و`visit.arrive` و`payment.updated`. عند إعادة الاتصال أو فتح التطبيق أو استلام Push، أعد قراءة البيانات من REST. إتاحة Push تتطلب FCM مهيّأ.

## قائمة عمليات HTTP

مدخلات الاستعلام والترويسات واسم DTO مستخرجة من تعريفات الكنترولر. قد يضيف منطق الخدمة شروطًا أخرى. المسار مثل `:id` يعني أن العميل يضع معرّف المورد فيه. لأشكال الاستجابات النهائية راجع المعالج المرتبط بكل صف.

### الدخول والكتالوج وطلبات المريض والزيارات المباشرة

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `POST /v1/auth/login` | تسجيل الدخول بالهاتف وكلمة المرور وتسليم رموز الجلسة | بدون JWT | جسم `LoginDto` | [login](../apps/api/src/auth/auth.controller.ts) |
| `POST /v1/auth/otp/request` | طلب إرسال رمز دخول لمرة واحدة حسب وضع المصادقة | بدون JWT | جسم `OtpRequestDto` | [request](../apps/api/src/auth/auth.controller.ts) |
| `POST /v1/auth/otp/verify` | التحقق من رمز الدخول وإصدار جلسة | بدون JWT | جسم `OtpVerifyDto` | [verify](../apps/api/src/auth/auth.controller.ts) |
| `POST /v1/auth/refresh` | تدوير رمز التجديد وإصدار رمز وصول جديد | بدون JWT | جسم `RefreshDto` | [refresh](../apps/api/src/auth/auth.controller.ts) |
| `POST /v1/auth/logout` | إنهاء الجلسة المرتبطة برمز التجديد | بدون JWT | جسم `LogoutDto` | [logout](../apps/api/src/auth/auth.controller.ts) |
| `GET /health` | فحص استجابة الخادم | بدون JWT | — | [health](../apps/api/src/app.controller.ts) |
| `GET /v1/categories` | عرض فئات الخدمات | بدون JWT | — | [categories](../apps/api/src/catalog/catalog.controller.ts) |
| `GET /v1/services` | عرض الخدمات المتاحة مع إمكانية التصفية حسب الفئة | بدون JWT | استعلام `category` | [services](../apps/api/src/catalog/catalog.controller.ts) |
| `POST /v1/catalog/estimate` | تقدير سعر مجموعة خدمات قبل إنشاء الطلب | بدون JWT | جسم `JSON` | [estimateServices](../apps/api/src/catalog/catalog.controller.ts) |
| `GET /v1/beneficiaries/mine` | عرض مستفيدي حساب المريض | PATIENT | — | [beneficiaries](../apps/api/src/catalog/catalog.controller.ts) |
| `POST /v1/requests` | إنشاء طلب زيارة مع مفتاح منع تكرار | PATIENT | جسم `CreateRequestDto`، ترويسة `idempotency-key` | [create](../apps/api/src/requests/requests.controller.ts) |
| `GET /v1/requests/scheduling` | قراءة سياسة المواعيد المجدولة | PATIENT | — | [scheduling](../apps/api/src/requests/requests.controller.ts) |
| `GET /v1/requests/mine` | عرض سجل طلبات المريض | PATIENT | استعلام `limit`، استعلام `cursor` | [list](../apps/api/src/requests/requests.controller.ts) |
| `GET /v1/requests/:id` | عرض تفاصيل طلب يخص المريض | PATIENT | — | [details](../apps/api/src/requests/requests.controller.ts) |
| `GET /v1/requests/:id/tracking` | عرض حالة الطلب والموقع المتاح للتتبّع | PATIENT | — | [track](../apps/api/src/requests/requests.controller.ts) |
| `GET /v1/requests/:id/cancellation-policy` | قراءة أهلية الإلغاء والتصنيف قبل التأكيد | PATIENT | — | [cancellationPolicy](../apps/api/src/requests/requests.controller.ts) |
| `POST /v1/requests/:id/cancel` | إلغاء الطلب وفق حالته وسياسة الإلغاء | PATIENT | جسم `CancelRequestDto` | [cancel](../apps/api/src/requests/requests.controller.ts) |
| `PUT /v1/nurse/me/availability` | تغيير حالة استعداد الممرض | NURSE | جسم `AvailabilityDto` | [availability](../apps/api/src/nurses/nurses.controller.ts) |
| `PUT /v1/nurse/me/location` | تحديث موقع الممرض ودقة القياس | NURSE | جسم `LocationDto` | [location](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/me/heartbeat` | تحديث آخر وقت حضور للممرض | NURSE | — | [heartbeat](../apps/api/src/nurses/nurses.controller.ts) |
| `GET /v1/nurse/me/history` | عرض تاريخ طلبات وزيارات الممرض | NURSE | استعلام `limit`، استعلام `cursor` | [history](../apps/api/src/nurses/nurses.controller.ts) |
| `GET /v1/nurse/me/offers` | عرض فرص التوزيع المباشر المتاحة للممرض | NURSE | — | [offers](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/offers/:offerId/accept` | قبول فرصة التوزيع المباشر وإسناد الطلب | NURSE | — | [accept](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/offers/:offerId/decline` | رفض فرصة التوزيع المباشر | NURSE | — | [decline](../apps/api/src/nurses/nurses.controller.ts) |
| `GET /v1/nurse/assignments/:id` | عرض تفاصيل طلب مسند للممرض | NURSE | — | [details](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/assignments/:id/depart` | تسجيل انطلاق الممرض | NURSE | — | [depart](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/assignments/:id/arrive` | تسجيل وصول الممرض | NURSE | — | [arrive](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/assignments/:id/start` | تسجيل بدء الخدمة | NURSE | — | [start](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/nurse/assignments/:id/complete` | تسجيل إكمال الزيارة | NURSE | — | [complete](../apps/api/src/nurses/nurses.controller.ts) |
| `POST /v1/visits/:id/patient-review` | إرسال تقييم المريض للزيارة | PATIENT | جسم `ReviewDto` | [patient](../apps/api/src/reviews/reviews.controller.ts) |
| `POST /v1/visits/:id/nurse-report` | إرسال تقرير الممرض عن الزيارة | NURSE | جسم `NurseReportDto` | [nurse](../apps/api/src/reviews/reviews.controller.ts) |
| `GET /v1/wallet/status` | فحص حالة وإتاحة المحفظة | PATIENT | — | [status](../apps/api/src/wallet/wallet.controller.ts) |
| `GET /v1/wallet/patient-summary` | عرض ملخص محفظة المريض | PATIENT | — | [patientSummary](../apps/api/src/wallet/wallet.controller.ts) |
| `POST /v1/wallet/topups` | مسار شحن المحفظة المسجّل، يعيد 501 في التنفيذ الحالي | PATIENT | — | [topup](../apps/api/src/wallet/wallet.controller.ts) |

### لوحة الإدارة والحسابات والكوادر والمناطق

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `PATCH /v1/admin/services/:id/visibility` | تحديث ظهور الخدمة | ADMIN | جسم `UpdateServiceVisibilityDto` | [updateVisibility](../apps/api/src/admin/admin.controller.ts) |
| `GET /v1/admin/dashboard` | عرض مؤشرات لوحة الإدارة | ADMIN | — | [dashboard](../apps/api/src/admin/admin.controller.ts) |
| `GET /v1/admin/requests` | عرض طلبات المنصة | ADMIN | استعلام `limit`، استعلام `cursor`، استعلام `status` | [requests](../apps/api/src/admin/admin.controller.ts) |
| `GET /v1/admin/nurses` | عرض قائمة تشغيلية للممرضين | ADMIN | استعلام `limit`، استعلام `cursor` | [nurses](../apps/api/src/admin/admin.controller.ts) |
| `GET /v1/admin/live` | عرض مؤشرات العمليات المباشرة | ADMIN | — | [live](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/dashboard/extras` | إظهار بيانات إضافية للوحة مثل الإيراد والحجوزات | ADMIN | — | [extras](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/bi/telemetry` | عرض مؤشرات تحليلية تشغيلية | ADMIN | — | [biTelemetry](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/nurses/summary` | عرض ملخص حالة الممرضين | ADMIN | — | [nursesSummary](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/credentials/pending` | عرض التراخيص بانتظار المراجعة | ADMIN / CLINICAL_REVIEWER | — | [pending](../apps/api/src/admin/admin-reports.controller.ts) |
| `POST /v1/admin/credentials/:id/decision` | تسجيل قرار مراجعة الترخيص | ADMIN / CLINICAL_REVIEWER | جسم `CredentialDecisionDto` | [decide](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/finance/summary` | عرض ملخص مالية المنصة | ADMIN | — | [finance](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/finance/settlements` | عرض سجل التسويات المالية | ADMIN | — | [settlements](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/wallet/reconciliation` | عرض معلومات مطابقة حسابات المحفظة حسب الإتاحة | ADMIN | — | [wallet](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/reviews/summary` | عرض مؤشرات التقييمات | ADMIN | — | [reviews](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/reviews/items` | عرض بنود التقييمات والتقارير | ADMIN | — | [reviewsItems](../apps/api/src/admin/admin-reports.controller.ts) |
| `GET /v1/admin/settings` | قراءة سياسات وإعدادات التشغيل | ADMIN | — | [settings](../apps/api/src/admin/admin-reports.controller.ts) |
| `POST /v1/admin/users` | إنشاء حساب من الإدارة | ADMIN | جسم `CreateUserDto` | [create](../apps/api/src/admin/admin-users.controller.ts) |
| `GET /v1/admin/users` | عرض الحسابات مع التصفية حسب الدور | ADMIN | استعلام `role`، استعلام `page` | [list](../apps/api/src/admin/admin-users.controller.ts) |
| `DELETE /v1/admin/users/:id` | إغلاق حساب وإنهاء جلساته مع إبقاء سجله المرجعي | ADMIN | — | [remove](../apps/api/src/admin/admin-users.controller.ts) |
| `POST /v1/admin/users/:id/status` | تفعيل حساب أو إيقافه | ADMIN | جسم `StatusDto` | [status](../apps/api/src/admin/admin-users.controller.ts) |
| `POST /v1/admin/users/:id/reset-password` | إصدار كلمة مرور مؤقتة لحساب | ADMIN | — | [reset](../apps/api/src/admin/admin-users.controller.ts) |
| `GET /v1/admin/nurses/manage` | البحث في دليل إدارة الممرضين | موظف مصادق حسب الصلاحية | استعلام `q`، استعلام `status`، استعلام `governorate`، استعلام `area` | [list](../apps/api/src/admin/admin-nurses.controller.ts) |
| `GET /v1/admin/nurses/:id/profile` | قراءة ملف الممرض الإداري | موظف مصادق حسب الصلاحية | — | [profile](../apps/api/src/admin/admin-nurses.controller.ts) |
| `POST /v1/admin/nurses/manage` | إنشاء حساب وملف ممرض من الإدارة | ADMIN | جسم `CreateNurseDto` | [create](../apps/api/src/admin/admin-nurses.controller.ts) |
| `PATCH /v1/admin/nurses/:id/profile` | تعديل بيانات ملف الممرض | ADMIN | جسم `UpdateNurseDto` | [update](../apps/api/src/admin/admin-nurses.controller.ts) |
| `POST /v1/admin/nurses/:id/status` | تفعيل حساب الممرض أو إيقافه | ADMIN | جسم `StatusDto` | [status](../apps/api/src/admin/admin-nurses.controller.ts) |
| `POST /v1/admin/nurses/:id/reset-password` | إصدار كلمة مرور مؤقتة للممرض | ADMIN | — | [resetPassword](../apps/api/src/admin/admin-nurses.controller.ts) |
| `DELETE /v1/admin/nurses/:id/profile` | إغلاق حساب الممرض مع إبقاء سجلات الزيارات | ADMIN | — | [remove](../apps/api/src/admin/admin-nurses.controller.ts) |
| `PUT /v1/admin/nurses/:id/skills` | تحديث مهارات وخدمات الممرض المعتمدة | موظف مصادق حسب الصلاحية | جسم `SkillsDto` | [skills](../apps/api/src/admin/admin-nurses.controller.ts) |
| `POST /v1/admin/nurses/:id/documents` | رفع وثيقة إلى ملف الممرض | موظف مصادق حسب الصلاحية | multipart، جسم `UploadDto` | [upload](../apps/api/src/admin/admin-nurses.controller.ts) |
| `GET /v1/admin/documents/:docId/download` | تنزيل وثيقة محمية | موظف مصادق حسب الصلاحية | — | [download](../apps/api/src/admin/admin-nurses.controller.ts) |
| `DELETE /v1/admin/documents/:docId` | حذف وثيقة وفق قواعد الاعتماد | ADMIN | — | [removeDoc](../apps/api/src/admin/admin-nurses.controller.ts) |
| `GET /v1/admin/system-settings` | قراءة إعدادات النظام | ADMIN | — | [all](../apps/api/src/admin/admin-settings.controller.ts) |
| `PUT /v1/admin/system-settings/:key` | تعديل مجموعة إعدادات محددة | ADMIN | جسم `JSON` | [save](../apps/api/src/admin/admin-settings.controller.ts) |
| `GET /v1/admin/audit` | عرض سجل التدقيق الإداري | ADMIN | استعلام `action`، استعلام `limit` | [audit](../apps/api/src/admin/admin-settings.controller.ts) |
| `GET /v1/admin/staff` | عرض المشرفين والمراجعين | ADMIN | — | [staff](../apps/api/src/admin/admin-settings.controller.ts) |
| `PATCH /v1/admin/staff/:id` | تعديل حساب مشرف أو مراجع | ADMIN | جسم `UpdateAdminDto` | [updateStaff](../apps/api/src/admin/admin-settings.controller.ts) |
| `DELETE /v1/admin/staff/:id` | إغلاق حساب مشرف أو مراجع | ADMIN | — | [deleteStaff](../apps/api/src/admin/admin-settings.controller.ts) |
| `GET /v1/catalog/regions` | عرض المحافظات والمناطق المتاحة | بدون JWT | — | [list](../apps/api/src/admin/regions.controller.ts) |
| `GET /v1/admin/regions` | عرض دليل المناطق للإدارة | ADMIN / CLINICAL_REVIEWER | — | [all](../apps/api/src/admin/regions.controller.ts) |
| `POST /v1/admin/regions/governorates` | إضافة محافظة | ADMIN | جسم `GovDto` | [addGov](../apps/api/src/admin/regions.controller.ts) |
| `PATCH /v1/admin/regions/governorates/:id` | تعديل محافظة | ADMIN | جسم `GovPatchDto` | [editGov](../apps/api/src/admin/regions.controller.ts) |
| `POST /v1/admin/regions/areas` | إضافة منطقة | ADMIN | جسم `AreaDto` | [addArea](../apps/api/src/admin/regions.controller.ts) |
| `PATCH /v1/admin/regions/areas/:id` | تعديل منطقة | ADMIN | جسم `AreaPatchDto` | [editArea](../apps/api/src/admin/regions.controller.ts) |

### التسجيل والجلسات والأجهزة ومسار الزيارة والفواتير

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `POST /v1/auth/register` | تسجيل حساب مريض جديد | بدون JWT | جسم `RegisterDto` | [patient](../apps/api/src/auth/registration.controller.ts) |
| `GET /v1/nurse/me/onboarding` | قراءة مرحلة انضمام الممرض وحالة وثائقه | NURSE | — | [status](../apps/api/src/auth/registration.controller.ts) |
| `POST /v1/nurse/me/documents` | رفع وثيقة اعتماد من حساب الممرض | NURSE | multipart، جسم `NurseDocDto` | [upload](../apps/api/src/auth/registration.controller.ts) |
| `POST /v1/auth/nurse-applications` | تقديم طلب انضمام ممرض مع الوثائق | بدون JWT | multipart، جسم `ApplyDto` | [apply](../apps/api/src/auth/applications.controller.ts) |
| `GET /v1/admin/applications` | عرض طلبات الانضمام | ADMIN / CLINICAL_REVIEWER | استعلام `status` | [list](../apps/api/src/auth/applications.controller.ts) |
| `GET /v1/admin/application-documents/:docId/download` | تنزيل وثيقة طلب انضمام | ADMIN / CLINICAL_REVIEWER | — | [download](../apps/api/src/auth/applications.controller.ts) |
| `POST /v1/admin/applications/:id/interview` | تعيين موعد مقابلة للممرض المتقدم | ADMIN | جسم `InterviewDto` | [interview](../apps/api/src/auth/applications.controller.ts) |
| `POST /v1/admin/applications/:id/reject` | رفض طلب الانضمام | ADMIN | جسم `RejectDto` | [reject](../apps/api/src/auth/applications.controller.ts) |
| `POST /v1/admin/applications/:id/approve` | اعتماد طلب الانضمام | ADMIN | — | [approve](../apps/api/src/auth/applications.controller.ts) |
| `GET /v1/auth/me` | جلب هوية صاحب الجلسة | مصادق حسب صلاحية المورد | — | [me](../apps/api/src/auth/account.controller.ts) |
| `GET /v1/auth/sessions` | عرض جلسات وأجهزة الحساب | مصادق حسب صلاحية المورد | — | [sessions](../apps/api/src/auth/account.controller.ts) |
| `POST /v1/auth/sessions/:id/revoke` | إلغاء جلسة جهاز محدد | مصادق حسب صلاحية المورد | — | [revokeSession](../apps/api/src/auth/account.controller.ts) |
| `POST /v1/auth/change-password` | تغيير كلمة مرور الحساب | مصادق حسب صلاحية المورد | جسم `ChangePasswordDto` | [change](../apps/api/src/auth/account.controller.ts) |
| `POST /v1/devices` | ربط رمز إشعارات FCM بالحساب | PATIENT / NURSE | جسم `DeviceDto` | [register](../apps/api/src/devices/devices.controller.ts) |
| `DELETE /v1/devices` | إزالة رمز FCM من الحساب | مصادق حسب صلاحية المورد | جسم `TokenDto` | [unregister](../apps/api/src/devices/devices.controller.ts) |
| `GET /v1/requests/:id/route` | قراءة مسار الزيارة من جانب المريض | PATIENT | — | [patient](../apps/api/src/maps/routes.controller.ts) |
| `GET /v1/nurse/assignments/:id/route` | قراءة مسار الزيارة من جانب الممرض | NURSE | — | [nurse](../apps/api/src/maps/routes.controller.ts) |
| `POST /v1/pricing/quote` | حساب عرض سعر الطلب | PATIENT | جسم `QuoteDto` | [quote](../apps/api/src/pricing/pricing.controller.ts) |
| `POST /v1/promos/claim` | المطالبة بكود خصم | PATIENT | جسم `ClaimDto` | [claim](../apps/api/src/pricing/pricing.controller.ts) |
| `GET /v1/requests/:id/bill` | قراءة الفاتورة من حساب المريض | PATIENT | — | [patientBill](../apps/api/src/pricing/pricing.controller.ts) |
| `GET /v1/nurse/requests/:id/bill` | قراءة الفاتورة من حساب الممرض | NURSE | — | [nurseBill](../apps/api/src/pricing/pricing.controller.ts) |
| `POST /v1/requests/:id/tip` | إضافة إكرامية للطلب عند إتاحتها | PATIENT | جسم `TipDto` | [tip](../apps/api/src/pricing/pricing.controller.ts) |
| `POST /v1/nurse/requests/:id/collect` | تسجيل المبلغ النقدي المحصّل | NURSE | جسم `CollectDto` | [collect](../apps/api/src/pricing/pricing.controller.ts) |

### إدارة الخدمات والرسوم والتوزيع

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/admin/services` | عرض كتالوج الخدمات للإدارة | ADMIN | — | [services](../apps/api/src/admin/admin-business.controller.ts) |
| `POST /v1/admin/services` | إنشاء خدمة | ADMIN | جسم `ServiceDto` | [createService](../apps/api/src/admin/admin-business.controller.ts) |
| `PATCH /v1/admin/services/:id` | تعديل بيانات خدمة أو أسعارها | ADMIN | جسم `ServiceDto` | [updateService](../apps/api/src/admin/admin-business.controller.ts) |
| `GET /v1/admin/promos` | عرض أكواد الخصم | ADMIN | — | [promos](../apps/api/src/admin/admin-business.controller.ts) |
| `POST /v1/admin/promos` | إنشاء كود خصم | ADMIN | جسم `PromoDto` | [createPromo](../apps/api/src/admin/admin-business.controller.ts) |
| `PATCH /v1/admin/promos/:id` | تعديل كود خصم | ADMIN | جسم `PromoDto` | [updatePromo](../apps/api/src/admin/admin-business.controller.ts) |
| `GET /v1/admin/leaderboard` | عرض ترتيب الممرضين حسب الفترة | ADMIN | استعلام `period` | [leaderboard](../apps/api/src/admin/admin-business.controller.ts) |
| `POST /v1/admin/rewards` | تسجيل مكافأة لممرض | ADMIN | جسم `RewardDto` | [reward](../apps/api/src/admin/admin-business.controller.ts) |
| `GET /v1/admin/rewards` | قراءة سجل المكافآت | ADMIN | — | [rewards](../apps/api/src/admin/admin-business.controller.ts) |
| `GET /v1/admin/pricing-settings` | قراءة إعدادات التسعير والرسوم | ADMIN | — | [settings](../apps/api/src/admin/admin-fees.controller.ts) |
| `PUT /v1/admin/pricing-settings` | تحديث إعدادات التسعير والرسوم | ADMIN | جسم `SettingsDto` | [updateSettings](../apps/api/src/admin/admin-fees.controller.ts) |
| `POST /v1/admin/holidays` | إضافة عطلة للتسعير | ADMIN | جسم `HolidayDto` | [addHoliday](../apps/api/src/admin/admin-fees.controller.ts) |
| `DELETE /v1/admin/holidays/:day` | حذف عطلة من التقويم | ADMIN | — | [removeHoliday](../apps/api/src/admin/admin-fees.controller.ts) |
| `POST /v1/admin/commission-tiers` | إضافة شريحة عمولة | ADMIN | جسم `TierDto` | [addTier](../apps/api/src/admin/admin-fees.controller.ts) |
| `PATCH /v1/admin/commission-tiers/:id` | تعديل شريحة عمولة | ADMIN | جسم `TierDto` | [updateTier](../apps/api/src/admin/admin-fees.controller.ts) |
| `DELETE /v1/admin/commission-tiers/:id` | حذف شريحة عمولة | ADMIN | — | [deleteTier](../apps/api/src/admin/admin-fees.controller.ts) |
| `GET /v1/admin/dues` | عرض رصيد مستحقات الممرضين | ADMIN | — | [allDues](../apps/api/src/admin/admin-fees.controller.ts) |
| `POST /v1/admin/dues/:nurseId/settle` | تسجيل تسوية مستحقات ممرض | ADMIN | جسم `SettleDto` | [settle](../apps/api/src/admin/admin-fees.controller.ts) |
| `GET /v1/admin/promos/abuse` | عرض مؤشرات إساءة استخدام الخصومات | ADMIN | — | [abuse](../apps/api/src/admin/admin-fees.controller.ts) |
| `GET /v1/admin/dispatch/diagnostics` | عرض تشخيص عملية توزيع الطلبات | ADMIN | — | [diagnostics](../apps/api/src/admin/admin-dispatch.controller.ts) |
| `GET /v1/admin/dispatch/requests/:id` | تشخيص توزيع طلب معيّن | ADMIN | — | [requestDiagnostics](../apps/api/src/admin/admin-dispatch.controller.ts) |
| `GET /v1/admin/notifications/health` | قراءة حالة منظومة الإشعارات | ADMIN | — | [notificationHealth](../apps/api/src/admin/admin-dispatch.controller.ts) |
| `GET /v1/admin/dispatch/export` | تصدير تقرير تشخيص التوزيع | ADMIN | استعلام `hours` | [exportTechnicalReport](../apps/api/src/admin/admin-dispatch.controller.ts) |

### التسويق والحسابات والالتزام والعناوين

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/admin/marketing` | عرض أدوات وميزات التسويق | ADMIN | — | [overview](../apps/api/src/admin/marketing.controller.ts) |
| `PUT /v1/admin/marketing/:key` | تغيير إعدادات أداة تسويق | ADMIN | جسم `FeatureDto` | [setFeature](../apps/api/src/admin/marketing.controller.ts) |
| `GET /v1/admin/marketing/packs` | عرض باقات الزيارات التسويقية | ADMIN | — | [packs](../apps/api/src/admin/marketing.controller.ts) |
| `POST /v1/admin/marketing/packs/grant` | منح باقة زيارات لمريض | ADMIN | جسم `GrantDto` | [grant](../apps/api/src/admin/marketing.controller.ts) |
| `GET /v1/admin/broadcasts/preview` | معاينة حجم جمهور الإرسال | ADMIN | استعلام `audience` | [preview](../apps/api/src/admin/marketing.controller.ts) |
| `POST /v1/admin/broadcasts` | وضع إشعار حملة في قائمة الإرسال | ADMIN | جسم `BroadcastDto` | [broadcast](../apps/api/src/admin/marketing.controller.ts) |
| `GET /v1/admin/broadcasts` | قراءة سجل الحملات وحالاتها | ADMIN | — | [history](../apps/api/src/admin/marketing.controller.ts) |
| `GET /v1/me/marketing-consent` | قراءة موافقة الإشعارات التسويقية | PATIENT | — | [get](../apps/api/src/auth/me.controller.ts) |
| `PUT /v1/me/marketing-consent` | تحديث موافقة الإشعارات التسويقية | PATIENT | جسم `ConsentDto` | [set](../apps/api/src/auth/me.controller.ts) |
| `GET /v1/me/active-request` | عرض الطلب النشط للحساب | PATIENT | — | [activeRequest](../apps/api/src/auth/me.controller.ts) |
| `GET /v1/referral/mine` | قراءة كود الإحالة الشخصي | PATIENT | — | [mine](../apps/api/src/pricing/referral.controller.ts) |
| `POST /v1/referral/claim` | تسجيل الإحالة عبر كود | PATIENT | جسم `ReferralClaimDto` | [claim](../apps/api/src/pricing/referral.controller.ts) |
| `GET /v1/nurse/me/summary` | عرض ملخص أداء الممرض | NURSE | — | [summary](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/nurse/me/earnings` | عرض الأرباح التقديرية للممرض | NURSE | — | [earnings](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/nurse/me/dues` | عرض مستحقات الممرض مع الشركة | NURSE | — | [duesView](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/nurse/me/profile` | عرض حالة ملف الممرض والاعتماد | NURSE | — | [profile](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/nurse/me/readiness` | عرض أهلية الممرض واستعداده للعمل | NURSE | — | [readiness](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/nurse/me/active-assignment` | عرض الإسناد النشط للممرض | NURSE | — | [activeAssignment](../apps/api/src/nurses/nurse-me.controller.ts) |
| `GET /v1/me/commitment` | قراءة سجل أو حالة الالتزام | PATIENT | — | [mine](../apps/api/src/requests/commitment.controller.ts) |
| `GET /v1/nurse/offers/:id/commitment` | قراءة أثر التزام مرتبط بعرض مباشر | NURSE | — | [offer](../apps/api/src/requests/commitment.controller.ts) |
| `POST /v1/cancellations/:id/appeals` | إرسال اعتراض على تصنيف إلغاء | PATIENT / NURSE | جسم `SubmitAppealDto` | [submit](../apps/api/src/requests/appeals.controller.ts) |
| `GET /v1/me/cancellation-appeals` | عرض اعتراضات صاحب الحساب | PATIENT / NURSE | — | [own](../apps/api/src/requests/appeals.controller.ts) |
| `GET /v1/admin/cancellation-appeals` | عرض طابور اعتراضات الإلغاء | ADMIN | — | [queue](../apps/api/src/requests/appeals.controller.ts) |
| `POST /v1/admin/cancellation-appeals/:id/review` | تسجيل قرار مراجعة اعتراض | ADMIN | جسم `ReviewAppealDto` | [review](../apps/api/src/requests/appeals.controller.ts) |
| `GET /v1/patient/saved-places` | عرض العناوين المحفوظة | PATIENT | — | [list](../apps/api/src/saved-places/saved-places.controller.ts) |
| `POST /v1/patient/saved-places` | حفظ عنوان جديد | PATIENT | جسم `SavedPlaceDto` | [create](../apps/api/src/saved-places/saved-places.controller.ts) |
| `PUT /v1/patient/saved-places/:id` | تعديل عنوان محفوظ | PATIENT | جسم `SavedPlaceDto` | [update](../apps/api/src/saved-places/saved-places.controller.ts) |
| `DELETE /v1/patient/saved-places/:id` | حذف عنوان محفوظ | PATIENT | — | [remove](../apps/api/src/saved-places/saved-places.controller.ts) |
| `POST /v1/patient/saved-places/:id/use` | تسجيل استخدام عنوان محفوظ | PATIENT | — | [use](../apps/api/src/saved-places/saved-places.controller.ts) |

### Guardian وسلامة الزيارة

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/safety/me/status` | قراءة حالة الحماية للحساب | NURSE | — | [status](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/nurse/safety/sessions/start` | بدء جلسة سلامة للممرض | NURSE | جسم `StartSafetySessionDto` | [start](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/nurse/safety/sessions/:id/locations/batch` | إرسال دفعة قياسات موقع لجلسة سلامة | NURSE | جسم `SafetyLocationBatchDto` | [locations](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/nurse/safety/sessions/:id/checkout` | إنهاء متابعة جلسة السلامة | NURSE | — | [checkout](../apps/api/src/safety/safety.controller.ts) |
| `GET /v1/nurse/safety/sessions/:id/checkin` | قراءة طلب الاطمئنان المعلق في الجلسة | NURSE | — | [pendingCheckin](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/nurse/safety/sessions/:id/checkin` | إرسال رد الممرض على طلب الاطمئنان | NURSE | جسم `SafetyCheckinResponseDto` | [respondCheckin](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/nurse/safety/assignments/:id/abort` | إنهاء الزيارة بأمان وفق قواعد التصعيد | NURSE | جسم `SafeAbortDto` | [abort](../apps/api/src/safety/safety.controller.ts) |
| `POST /v1/safety/sos` | إرسال استغاثة مرتبطة بالسياق المسموح | NURSE | جسم `ReportSosDto` | [sos](../apps/api/src/safety/safety.controller.ts) |
| `GET /v1/safety/events/:id` | قراءة حدث سلامة مسموح للحساب | NURSE | — | [event](../apps/api/src/safety/safety.controller.ts) |
| `GET /v1/admin/safety/dashboard` | عرض مؤشرات عمليات السلامة | ADMIN / CLINICAL_REVIEWER | — | [dashboard](../apps/api/src/safety/staff-cases.controller.ts) |
| `GET /v1/admin/safety/events` | عرض بلاغات وأحداث السلامة | ADMIN / CLINICAL_REVIEWER | — | [list](../apps/api/src/safety/staff-cases.controller.ts) |
| `GET /v1/admin/safety/events/:id` | عرض تفاصيل حادث سلامة | ADMIN / CLINICAL_REVIEWER | — | [detail](../apps/api/src/safety/staff-cases.controller.ts) |
| `POST /v1/admin/safety/events/:id/acknowledge` | تسجيل استلام البلاغ | ADMIN / CLINICAL_REVIEWER | جسم `SafetyCaseActionDto` | [acknowledge](../apps/api/src/safety/staff-cases.controller.ts) |
| `POST /v1/admin/safety/events/:id/escalate` | تصعيد البلاغ | ADMIN / CLINICAL_REVIEWER | جسم `SafetyCaseActionDto` | [escalate](../apps/api/src/safety/staff-cases.controller.ts) |
| `POST /v1/admin/safety/events/:id/resolve` | تسجيل معالجة البلاغ | ADMIN / CLINICAL_REVIEWER | جسم `SafetyCaseActionDto` | [resolve](../apps/api/src/safety/staff-cases.controller.ts) |
| `GET /v1/admin/safety/events/:id/handover-candidates` | عرض المرشحين لاستلام متابعة الحالة | ADMIN / CLINICAL_REVIEWER | — | [candidates](../apps/api/src/safety/staff-cases.controller.ts) |
| `GET /v1/admin/safety/handovers` | عرض طلبات تسليم المتابعة | ADMIN / CLINICAL_REVIEWER | — | [inbox](../apps/api/src/safety/staff-cases.controller.ts) |
| `POST /v1/admin/safety/events/:id/handover` | إرسال طلب تسليم متابعة الحالة | ADMIN / CLINICAL_REVIEWER | جسم `HandoverDto` | [handover](../apps/api/src/safety/staff-cases.controller.ts) |
| `POST /v1/admin/safety/handovers/:id/accept` | قبول تسليم الحالة | ADMIN / CLINICAL_REVIEWER | — | [accept](../apps/api/src/safety/staff-cases.controller.ts) |
| `GET /v1/me/trusted-contacts` | عرض جهات الاتصال الموثوقة | PATIENT / NURSE | — | [list](../apps/api/src/trusted-contacts/trusted-contacts.controller.ts) |
| `POST /v1/me/trusted-contacts` | إضافة جهة اتصال موثوقة | PATIENT / NURSE | جسم `TrustedContactDto` | [create](../apps/api/src/trusted-contacts/trusted-contacts.controller.ts) |
| `PUT /v1/me/trusted-contacts/:id` | تعديل جهة اتصال موثوقة | PATIENT / NURSE | جسم `TrustedContactDto` | [update](../apps/api/src/trusted-contacts/trusted-contacts.controller.ts) |
| `DELETE /v1/me/trusted-contacts/:id` | إزالة جهة من القائمة الموثوقة | PATIENT / NURSE | — | [remove](../apps/api/src/trusted-contacts/trusted-contacts.controller.ts) |
| `POST /v1/admin/safety/trusted-contacts/:id/consent` | تسجيل موافقة جهة اتصال عبر الإدارة | ADMIN / CLINICAL_REVIEWER | جسم `ContactConsentDto` | [consent](../apps/api/src/trusted-contacts/trusted-contacts.controller.ts) |
| `GET /v1/safety/directory` | عرض دليل الطوارئ المتاح للحساب | PATIENT / NURSE | — | [visible](../apps/api/src/safety/directory.controller.ts) |
| `GET /v1/admin/safety/directory` | عرض دليل الطوارئ كما تراه الإدارة | ADMIN / CLINICAL_REVIEWER | — | [list](../apps/api/src/safety/directory.controller.ts) |
| `POST /v1/admin/safety/directory` | إضافة بند إلى دليل الطوارئ | ADMIN / CLINICAL_REVIEWER | جسم `DirectoryEntryDto` | [create](../apps/api/src/safety/directory.controller.ts) |
| `PUT /v1/admin/safety/directory/:id` | تعديل بند في دليل الطوارئ | ADMIN / CLINICAL_REVIEWER | جسم `DirectoryEntryDto` | [edit](../apps/api/src/safety/directory.controller.ts) |
| `DELETE /v1/admin/safety/directory/:id` | تعطيل بند في دليل الطوارئ | ADMIN / CLINICAL_REVIEWER | — | [deactivate](../apps/api/src/safety/directory.controller.ts) |
| `GET /v1/admin/safety/shifts` | عرض مناوبات عمليات السلامة | ADMIN / CLINICAL_REVIEWER | — | [list](../apps/api/src/safety/shifts.controller.ts) |
| `POST /v1/admin/safety/shifts` | إنشاء مناوبة سلامة | ADMIN / CLINICAL_REVIEWER | جسم `SafetyShiftDto` | [create](../apps/api/src/safety/shifts.controller.ts) |
| `PUT /v1/admin/safety/shifts/:id` | تعديل مناوبة سلامة | ADMIN / CLINICAL_REVIEWER | جسم `SafetyShiftDto` | [edit](../apps/api/src/safety/shifts.controller.ts) |
| `DELETE /v1/admin/safety/shifts/:id` | إلغاء مناوبة سلامة | ADMIN / CLINICAL_REVIEWER | — | [cancel](../apps/api/src/safety/shifts.controller.ts) |
| `POST /v1/admin/safety/shifts/:id/checkin` | تسجيل مباشرة مناوبة | ADMIN / CLINICAL_REVIEWER | — | [checkin](../apps/api/src/safety/shifts.controller.ts) |
| `POST /v1/admin/safety/shifts/:id/heartbeat` | تحديث حضور المشرف في المناوبة | ADMIN / CLINICAL_REVIEWER | — | [heartbeat](../apps/api/src/safety/shifts.controller.ts) |
| `POST /v1/admin/safety/shifts/:id/checkout` | إنهاء حضور المشرف في المناوبة | ADMIN / CLINICAL_REVIEWER | — | [checkout](../apps/api/src/safety/shifts.controller.ts) |
| `GET /v1/admin/safety/night-policy` | عرض قواعد العمل الليلي | ADMIN / CLINICAL_REVIEWER | — | [rules](../apps/api/src/safety/night-policy.controller.ts) |
| `POST /v1/admin/safety/night-policy` | نشر قاعدة عمل ليلي | ADMIN / CLINICAL_REVIEWER | جسم `NightPolicyDto` | [publish](../apps/api/src/safety/night-policy.controller.ts) |
| `GET /v1/nurse/safety/night-preference` | قراءة تفضيل الممرض للعمل الليلي | NURSE | — | [preference](../apps/api/src/safety/night-policy.controller.ts) |
| `PUT /v1/nurse/safety/night-preference` | تحديث تفضيل العمل الليلي | NURSE | جسم `NightPreferenceDto` | [update](../apps/api/src/safety/night-policy.controller.ts) |
| `GET /v1/admin/safety/review-queue` | عرض طابور مراجعة مخاطر الزيارات | ADMIN / CLINICAL_REVIEWER | — | [queue](../apps/api/src/safety/visit-risk.controller.ts) |
| `POST /v1/admin/safety/requests/:id/risk` | تسجيل تقييم مخاطر زيارة | ADMIN / CLINICAL_REVIEWER | جسم `VisitRiskDto` | [assess](../apps/api/src/safety/visit-risk.controller.ts) |
| `POST /v1/admin/safety/requests/:id/companion` | ترشيح مرافق للزيارة | ADMIN / CLINICAL_REVIEWER | جسم `VisitCompanionDto` | [nominate](../apps/api/src/safety/visit-risk.controller.ts) |
| `GET /v1/nurse/safety/companions` | عرض ترشيحات المرافقة المعلقة | NURSE | — | [pending](../apps/api/src/safety/visit-risk.controller.ts) |
| `POST /v1/nurse/safety/companions/:id/confirm` | تأكيد ترشيح المرافقة | NURSE | جسم `ConfirmVisitCompanionDto` | [confirm](../apps/api/src/safety/visit-risk.controller.ts) |
| `POST /v1/admin/safety/events/:id/export-approvals` | اعتماد تصدير أدلة حالة | ADMIN / CLINICAL_REVIEWER | جسم `EvidenceApprovalDto` | [approve](../apps/api/src/safety/evidence.controller.ts) |
| `POST /v1/admin/safety/events/:id/export` | توليد حزمة أدلة وفق الصلاحية | ADMIN / CLINICAL_REVIEWER | جسم `EvidenceExportDto` | [generate](../apps/api/src/safety/evidence.controller.ts) |
| `GET /v1/admin/safety/exports/:id` | تنزيل حزمة أدلة محمية | ADMIN / CLINICAL_REVIEWER | — | [download](../apps/api/src/safety/evidence.controller.ts) |
| `GET /v1/admin/safety/retention-policy` | قراءة سياسة الاحتفاظ بالأدلة | ADMIN / CLINICAL_REVIEWER | — | [status](../apps/api/src/safety/retention.controller.ts) |
| `POST /v1/admin/safety/retention-policy` | تعيين سياسة الاحتفاظ | ADMIN / CLINICAL_REVIEWER | جسم `RetentionPolicyDto` | [configure](../apps/api/src/safety/retention.controller.ts) |
| `GET /v1/admin/safety/events/:id/legal-holds` | عرض أوامر الحفظ القانوني للحالة | ADMIN / CLINICAL_REVIEWER | — | [holds](../apps/api/src/safety/retention.controller.ts) |
| `POST /v1/admin/safety/events/:id/legal-holds` | تفعيل حفظ قانوني لأدلة الحالة | ADMIN / CLINICAL_REVIEWER | جسم `LegalHoldDto` | [hold](../apps/api/src/safety/retention.controller.ts) |
| `POST /v1/admin/safety/events/:id/legal-holds/:holdId/release` | رفع حفظ قانوني وفق الصلاحية | ADMIN / CLINICAL_REVIEWER | جسم `ReleaseHoldDto` | [release](../apps/api/src/safety/retention.controller.ts) |

### المحادثات والدعم والتقويم والرعاية المتكررة

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/conversations` | عرض محادثات الحساب | مصادق حسب صلاحية المورد | — | [list](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/conversations/visit/:requestId` | فتح محادثة مرتبطة بزيارة | مصادق حسب صلاحية المورد | — | [openVisitConversation](../apps/api/src/chat/chat.controller.ts) |
| `GET /v1/conversations/:id/messages` | عرض رسائل محادثة | مصادق حسب صلاحية المورد | استعلام `limit`، استعلام `before` | [messages](../apps/api/src/chat/chat.controller.ts) |
| `GET /v1/chat/requests/:requestId/messages` | عرض رسائل محادثة طلب عبر مسار الطلب | مصادق حسب صلاحية المورد | — | [requestMessages](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/chat/messages` | إرسال رسالة عبر مسار المحادثة المبسط | مصادق حسب صلاحية المورد | جسم `JSON` | [postChatMessage](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/conversations/:id/messages` | إرسال رسالة إلى محادثة محددة | مصادق حسب صلاحية المورد | جسم `SendMessageDto` | [sendMessage](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/conversations/:id/read` | تسجيل قراءة رسائل المحادثة | مصادق حسب صلاحية المورد | جسم `MarkReadDto` | [markRead](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/conversations/:id/attachments` | رفع مرفق آمن إلى محادثة | مصادق حسب صلاحية المورد | جسم `AttachmentMetadataDto` | [uploadAttachment](../apps/api/src/chat/chat.controller.ts) |
| `POST /v1/blocks` | حظر مستخدم | مصادق حسب صلاحية المورد | جسم `BlockUserDto` | [block](../apps/api/src/trust/trust.controller.ts) |
| `GET /v1/blocks` | عرض المستخدمين المحظورين | مصادق حسب صلاحية المورد | — | [listBlocks](../apps/api/src/trust/trust.controller.ts) |
| `DELETE /v1/blocks/:targetUserId` | إلغاء حظر مستخدم | مصادق حسب صلاحية المورد | — | [unblock](../apps/api/src/trust/trust.controller.ts) |
| `POST /v1/reports` | إرسال بلاغ دعم أو سلوك | مصادق حسب صلاحية المورد | جسم `CreateReportDto` | [submitReport](../apps/api/src/trust/trust.controller.ts) |
| `GET /v1/admin/support-reports` | عرض بلاغات الدعم للإدارة | ADMIN | استعلام `status`، استعلام `type` | [listReports](../apps/api/src/trust/trust.controller.ts) |
| `POST /v1/trust/reports/:id/triage` | تسجيل قرار فرز بلاغ | ADMIN | جسم `JSON` | [triageReport](../apps/api/src/trust/trust.controller.ts) |
| `GET /v1/nurse-calendar` | عرض تقويم الممرض ومواعيد عدم التوفر | NURSE | استعلام `from`، استعلام `to` | [getSchedule](../apps/api/src/scheduling/calendar.controller.ts) |
| `POST /v1/nurse-calendar/blocks` | إضافة فترة عدم توفر | NURSE | جسم `AddCalendarBlockDto` | [addBlock](../apps/api/src/scheduling/calendar.controller.ts) |
| `DELETE /v1/nurse-calendar/blocks/:id` | إزالة فترة عدم توفر | NURSE | — | [removeBlock](../apps/api/src/scheduling/calendar.controller.ts) |
| `POST /v1/care-plans` | إنشاء خطة رعاية متكررة | PATIENT | جسم `CreateCarePlanInputDto` | [create](../apps/api/src/care-plans/care-plans.controller.ts) |
| `GET /v1/care-plans` | عرض خطط رعاية المريض | PATIENT / ADMIN | — | [list](../apps/api/src/care-plans/care-plans.controller.ts) |
| `GET /v1/care-plans/:id` | قراءة خطة رعاية ومواعيدها | PATIENT / ADMIN | — | [getOne](../apps/api/src/care-plans/care-plans.controller.ts) |
| `POST /v1/care-plans/:id/pause` | إيقاف خطة رعاية مؤقتًا | PATIENT | — | [pause](../apps/api/src/care-plans/care-plans.controller.ts) |
| `POST /v1/care-plans/:id/resume` | استئناف خطة رعاية | PATIENT | — | [resume](../apps/api/src/care-plans/care-plans.controller.ts) |
| `POST /v1/care-plans/:id/cancel` | إلغاء خطة رعاية | PATIENT | — | [cancel](../apps/api/src/care-plans/care-plans.controller.ts) |

### البيانات السريرية والباقات والاتصال والإشعارات

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/beneficiaries/:id/health-record` | قراءة الملف الصحي لمستفيد مصرح | مصادق حسب صلاحية المورد | استعلام `requestId` | [getProfile](../apps/api/src/health-records/health-records.controller.ts) |
| `PUT /v1/beneficiaries/:id/health-record` | تحديث الملف الصحي للمستفيد | PATIENT | جسم `JSON` | [updateProfile](../apps/api/src/health-records/health-records.controller.ts) |
| `GET /v1/beneficiaries/:id/observations` | قراءة القياسات والملاحظات السريرية للمستفيد | مصادق حسب صلاحية المورد | استعلام `type`، استعلام `limit` | [getObservations](../apps/api/src/health-records/health-records.controller.ts) |
| `POST /v1/beneficiaries/:id/observations` | إضافة قياسات لمستفيد | مصادق حسب صلاحية المورد | جسم `RecordObservationsDto` | [recordObservations](../apps/api/src/health-records/health-records.controller.ts) |
| `GET /v1/visits/:requestId/form-config` | قراءة إعداد نموذج الزيارة السريري | NURSE | — | [getFormConfig](../apps/api/src/health-records/health-records.controller.ts) |
| `POST /v1/visits/:requestId/clinical-notes` | حفظ ملاحظات الزيارة السريرية | NURSE | جسم `SaveVisitNoteDto` | [saveVisitNotes](../apps/api/src/health-records/health-records.controller.ts) |
| `GET /v1/visits/:requestId/clinical-notes` | قراءة ملاحظات الزيارة السريرية | مصادق حسب صلاحية المورد | — | [getVisitNotes](../apps/api/src/health-records/health-records.controller.ts) |
| `POST /v1/health-records/observations` | إرسال القياسات عبر واجهة السجلات الصحية | مصادق حسب صلاحية المورد | جسم `JSON` | [postHealthObservations](../apps/api/src/health-records/health-records.controller.ts) |
| `POST /v1/health-records/notes` | إرسال الملاحظات عبر واجهة السجلات الصحية | NURSE | جسم `JSON` | [postHealthNotes](../apps/api/src/health-records/health-records.controller.ts) |
| `GET /v1/health-records/profiles` | عرض الملفات الصحية المتاحة للحساب | مصادق حسب صلاحية المورد | استعلام `beneficiaryId` | [getHealthProfiles](../apps/api/src/health-records/health-records.controller.ts) |
| `GET /v1/visits/:requestId/clinical-report` | قراءة التقرير السريري المنظم للزيارة | مصادق حسب صلاحية المورد | — | [getReport](../apps/api/src/clinical-reports/clinical-reports.controller.ts) |
| `GET /v1/visits/:requestId/clinical-report/html` | عرض التقرير السريري بصيغة HTML | مصادق حسب صلاحية المورد | — | [getReportHtml](../apps/api/src/clinical-reports/clinical-reports.controller.ts) |
| `GET /v1/clinical-reports/verify/:token` | التحقق من التقرير عبر رمز التحقق | بدون JWT | — | [verifyReport](../apps/api/src/clinical-reports/clinical-reports.controller.ts) |
| `GET /v1/favorites/nurses` | عرض الممرضين المفضلين | PATIENT | — | [list](../apps/api/src/nurses/favorites.controller.ts) |
| `POST /v1/favorites/nurses/:id` | حفظ ممرض في المفضلة | PATIENT | — | [add](../apps/api/src/nurses/favorites.controller.ts) |
| `DELETE /v1/favorites/nurses/:id` | إزالة ممرض من المفضلة | PATIENT | — | [remove](../apps/api/src/nurses/favorites.controller.ts) |
| `GET /v1/packages` | عرض الباقات المتاحة | بدون JWT | — | [list](../apps/api/src/marketing/packages.controller.ts) |
| `GET /v1/packages/mine` | قراءة باقات الحساب | PATIENT | — | [listMine](../apps/api/src/marketing/packages.controller.ts) |
| `POST /v1/packages/:id/purchase` | شراء باقة حسب سياسة الإتاحة | PATIENT | — | [purchase](../apps/api/src/marketing/packages.controller.ts) |
| `GET /v1/nurse/financial/summary` | عرض الملخص المالي للممرض | NURSE | — | [getSummary](../apps/api/src/nurses/nurse-financial.controller.ts) |
| `GET /v1/nurse/financial/ledger` | قراءة حركات دفتر الممرض المالي | NURSE | استعلام `limit` | [getLedger](../apps/api/src/nurses/nurse-financial.controller.ts) |
| `POST /v1/calls/initiate` | بدء مكالمة مرتبطة بطلب | مصادق حسب صلاحية المورد | جسم `InitiateCallInputDto` | [initiate](../apps/api/src/voice/voice.controller.ts) |
| `POST /v1/calls/:id/accept` | قبول مكالمة | مصادق حسب صلاحية المورد | — | [accept](../apps/api/src/voice/voice.controller.ts) |
| `POST /v1/calls/:id/reject` | رفض مكالمة | مصادق حسب صلاحية المورد | جسم `EndCallInputDto` | [reject](../apps/api/src/voice/voice.controller.ts) |
| `POST /v1/calls/:id/end` | إنهاء مكالمة | مصادق حسب صلاحية المورد | جسم `EndCallInputDto` | [end](../apps/api/src/voice/voice.controller.ts) |
| `POST /v1/calls/:id/signal` | إرسال إشارة تفاوض الاتصال الصوتي | مصادق حسب صلاحية المورد | جسم `CallSignalInputDto` | [signal](../apps/api/src/voice/voice.controller.ts) |
| `GET /v1/calls/:id` | قراءة حالة مكالمة | مصادق حسب صلاحية المورد | — | [getCall](../apps/api/src/voice/voice.controller.ts) |
| `GET /v1/notifications` | عرض مركز إشعارات الحساب | مصادق حسب صلاحية المورد | استعلام `limit`، استعلام `offset`، استعلام `unreadOnly` | [list](../apps/api/src/notifications/notifications.controller.ts) |
| `POST /v1/notifications/:id/read` | تمييز إشعار كمقروء | مصادق حسب صلاحية المورد | — | [markAsRead](../apps/api/src/notifications/notifications.controller.ts) |
| `POST /v1/notifications/read-all` | تمييز جميع الإشعارات كمقروءة | مصادق حسب صلاحية المورد | — | [markAllAsRead](../apps/api/src/notifications/notifications.controller.ts) |
| `GET /v1/notifications/preferences` | قراءة تفضيلات الإشعارات | مصادق حسب صلاحية المورد | — | [getPreferences](../apps/api/src/notifications/notifications.controller.ts) |
| `PUT /v1/notifications/preferences` | تحديث تفضيلات الإشعارات | مصادق حسب صلاحية المورد | جسم `UpdatePreferencesInputDto` | [updatePreferences](../apps/api/src/notifications/notifications.controller.ts) |

### السوق المفتوح والحجز الذكي وسجل الزيارة المجدولة

| العملية | الاستخدام | الوصول | المدخلات | المصدر |
|---|---|---|---|---|
| `GET /v1/marketplace/requests` | تصفح السوق المفتوح المتاح للممرض | NURSE | استعلام `MarketplaceQueryDto` | [listRequests](../apps/api/src/marketplace/marketplace.controller.ts) |
| `GET /v1/marketplace/requests/:id` | قراءة تفاصيل طلب مفتوح مع حماية الموقع قبل الإسناد | NURSE | — | [getRequestDetails](../apps/api/src/marketplace/marketplace.controller.ts) |
| `POST /v1/marketplace/requests/:id/proposals` | إرسال عرض جاهزية بوقت وصول تقديري وملاحظة اختيارية | NURSE | جسم `SubmitProposalDto` | [submitProposal](../apps/api/src/marketplace/marketplace.controller.ts) |
| `POST /v1/marketplace/requests/:id/save` | حفظ طلب سوق للمراجعة | NURSE | — | [saveRequest](../apps/api/src/marketplace/marketplace.controller.ts) |
| `DELETE /v1/marketplace/requests/:id/save` | إزالة طلب سوق من المحفوظات | NURSE | — | [unsaveRequest](../apps/api/src/marketplace/marketplace.controller.ts) |
| `GET /v1/marketplace/proposals/mine` | عرض عروض الجاهزية التي أرسلها الممرض | NURSE | استعلام `status` | [listMyProposals](../apps/api/src/marketplace/marketplace.controller.ts) |
| `POST /v1/marketplace/proposals/:id/withdraw` | سحب عرض جاهزية قبل قبوله | NURSE | جسم `WithdrawProposalDto` | [withdrawProposal](../apps/api/src/marketplace/marketplace.controller.ts) |
| `GET /v1/requests/:id/proposals` | عرض عروض الجاهزية المستلمة لطلب المريض | PATIENT | — | [listProposals](../apps/api/src/marketplace/proposals.controller.ts) |
| `POST /v1/requests/:id/proposals/:proposalId/accept` | قبول عرض واحد وإسناد الطلب للممرض | PATIENT | جسم `AcceptProposalDto` | [acceptProposal](../apps/api/src/marketplace/proposals.controller.ts) |
| `POST /v1/requests/:id/proposals/:proposalId/decline` | رفض عرض جاهزية | PATIENT | — | [declineProposal](../apps/api/src/marketplace/proposals.controller.ts) |
| `POST /v1/requests/:id/booking-mode` | تغيير وضع الحجز حسب حالة الطلب | PATIENT | جسم `SwitchBookingModeDto` | [switchBookingMode](../apps/api/src/marketplace/booking-mode.controller.ts) |
| `POST /v1/requests/:id/retry-dispatch` | إعادة محاولة التوزيع للطلب المؤهل | PATIENT | — | [retryDispatch](../apps/api/src/marketplace/booking-mode.controller.ts) |
| `POST /v1/requests/:id/open/extend` | تمديد استقبال العروض لطلب مفتوح | PATIENT | جسم `ExtendOpenRequestDto` | [extendOpen](../apps/api/src/marketplace/booking-mode.controller.ts) |
| `GET /v1/admin/booking/policies` | قراءة سياسات الحجز والسوق | ADMIN | — | [getPolicies](../apps/api/src/admin/admin-booking.controller.ts) |
| `PATCH /v1/admin/booking/policies` | تحديث سياسات الحجز والسوق | ADMIN | جسم `JSON` | [updatePolicies](../apps/api/src/admin/admin-booking.controller.ts) |
| `GET /v1/admin/booking/requests` | عرض الطلبات للإدارة مع مرشحات الحجز | ADMIN | استعلام `bookingMode`، استعلام `status`، استعلام `limit` | [listRequests](../apps/api/src/admin/admin-booking.controller.ts) |
| `GET /v1/admin/booking/proposals` | عرض عروض الجاهزية للإدارة | ADMIN | استعلام `status`، استعلام `requestId`، استعلام `nurseId` | [listProposals](../apps/api/src/admin/admin-booking.controller.ts) |
| `GET /v1/admin/booking/analytics` | عرض مؤشرات استعمال أنماط الحجز | ADMIN | — | [getAnalytics](../apps/api/src/admin/admin-booking.controller.ts) |
| `GET /v1/admin/requests/:id/visit-record` | قراءة سجل تنفيذ الزيارة والعنوان والأوقات والتحصيل المسجل | ADMIN | — | [get](../apps/api/src/admin/request-record.controller.ts) |
| `GET /v1/admin/schedule/visits` | عرض الزيارات المجدولة أو المؤرشفة مع المكلّف والوصول المسجل | ADMIN | استعلام `removed`، استعلام `page` | [visits](../apps/api/src/admin/admin-schedule.controller.ts) |
| `GET /v1/admin/schedule/care-plans` | عرض خطط الرعاية المجدولة للإدارة | ADMIN | استعلام `page` | [plans](../apps/api/src/admin/admin-schedule.controller.ts) |
| `DELETE /v1/admin/schedule/visits/:id` | أرشفة زيارة منتهية أو إلغاء وأرشفة موعد غير مسند مع حفظ السجل | ADMIN | — | [remove](../apps/api/src/admin/admin-schedule.controller.ts) |

## حقول DTO المعرّفة بواسطة قواعد التحقق

علامة «؟» تعني أن الحقل اختياري حسب DTO. بعض التوليفات لها شروط إضافية في الخدمة، مثل وجوب اختيار طريقة لتحديد الوصول عند إرسال عرض.

| DTO | الحقول |
|---|---|
| `AcceptProposalDto` | `proposalVersion`؟، `requestVersion`؟ |
| `AddCalendarBlockDto` | `startTime`، `endTime`، `reason`؟ |
| `ApplyDto` | `phone`، `displayName`، `governorateId`، `areaId`، `specialty`؟، `nationalId`؟، `docKind`، `licenseRef`، `expiresAt`، `acceptTerms` |
| `AreaDto` | `governorateId`، `lat`؟، `lng`؟، `nameAr`، `sortOrder`؟ |
| `AreaPatchDto` | `lat`؟، `lng`؟، `nameAr`؟، `active`؟، `sortOrder`؟ |
| `AttachmentMetadataDto` | `filename`، `mimeType`، `sizeBytes`، `isPrescription`؟ |
| `AvailabilityDto` | `availability` |
| `BlockUserDto` | `targetUserId`، `reasonCode`؟، `privateNote`؟ |
| `BroadcastDto` | `audience`، `title`، `body`، `promoCode`؟ |
| `CallSignalInputDto` | `eventType`، `data` |
| `CancelRequestDto` | `reasonCode`؟، `reasonNote`؟، `idempotencyKey`؟، `expectedVersion`؟، `policyAcknowledged`؟ |
| `ChangePasswordDto` | `currentPassword`، `newPassword` |
| `ClaimDto` | `code` |
| `CollectDto` | `amount` |
| `ConfirmVisitCompanionDto` | `nurseId` |
| `ConsentDto` | `optIn` |
| `ContactConsentDto` | `decision`، `allowsLocation`، `verificationReference`، `verifiedPhone` |
| `CreateCarePlanInputDto` | `beneficiaryId`، `primaryServiceId`، `frequencyType`، `frequencyMeta`؟، `preferredTimeOfDay`، `totalVisitsPlanned`؟، `startDate`، `endDate`؟، `notes`؟، `addressText`، `latitude`، `longitude`، `locationSource`؟ |
| `CreateNurseDto` | `phone`، `displayName`، `password`؟، `governorateId`؟، `areaId`؟، `specialty`؟، `nationalId`؟، `notes`؟، `nurseNo`؟ |
| `CreateReportDto` | `reportedUserId`؟، `requestId`؟، `reportType`، `severity`؟، `title`، `description` |
| `CreateRequestDto` | `scheduledAt`؟، `bookingMode`؟، `latestAcceptableArrivalAt`؟، `openDurationMinutes`؟، `beneficiaryId`، `serviceId`؟، `serviceIds`؟، `items`؟، `locationSource`، `addressText`، `nonEmergencyConfirmed`، `prescriptionConfirmed`؟، `promoCode`؟، `latitude`، `longitude`، `accuracyMeters` |
| `CreateUserDto` | `phone`، `role`، `displayName`، `password`؟، `beneficiaryName`؟، `licenseRef`؟، `licenseExpiresAt`؟ |
| `CredentialDecisionDto` | `decision`، `reason`؟ |
| `DeviceDto` | `token`، `platform` |
| `DirectoryEntryDto` | `name`، `category`، `governorate`؟، `area`؟، `dialNumber`، `hours`؟، `officialSource`، `publishVerified` |
| `EndCallInputDto` | `reason`؟ |
| `EvidenceApprovalDto` | `exporterId`، `purpose`، `recipient`، `caseReference`؟ |
| `EvidenceExportDto` | `approvalId` |
| `ExtendOpenRequestDto` | `additionalMinutes` |
| `FeatureDto` | `enabled`؟، `config`؟ |
| `GovDto` | `nameAr`، `sortOrder`؟ |
| `GovPatchDto` | `nameAr`؟، `active`؟، `sortOrder`؟ |
| `GrantDto` | `phone`، `name`، `visits`، `percent`، `validDays` |
| `HandoverDto` | `toUserId`، `toShiftId`، `expectedVersion` |
| `HolidayDto` | `day`، `name` |
| `InitiateCallInputDto` | `requestId` |
| `InterviewDto` | `interviewAt`، `note`؟ |
| `LegalHoldDto` | `reason`، `reference` |
| `LocationDto` | `latitude`، `longitude`، `accuracyMeters` |
| `LoginDto` | `phone`، `password`، `deviceId`؟، `deviceName`؟، `platform`؟ |
| `LogoutDto` | `refreshToken`؟، `deviceId`؟ |
| `MarketplaceQueryDto` | `sortBy`؟، `serviceId`؟، `regionId`؟، `maxDistanceKm`؟، `limit`؟، `cursor`؟ |
| `MarkReadDto` | `messageId` |
| `NightPolicyDto` | `governorateId`؟، `areaId`؟، `serviceId`؟، `mode`، `startsAt`، `endsAt` |
| `NightPreferenceDto` | `optedIn` |
| `NurseDocDto` | `kind`، `licenseRef`؟، `expiresAt`؟ |
| `NurseReportDto` | `category`، `note`؟، `stars`؟ |
| `OtpRequestDto` | `phone`، `channel`؟ |
| `OtpVerifyDto` | `phone`، `code`، `deviceId`؟، `deviceName`؟، `platform`؟ |
| `PromoDto` | `code`؟، `description`؟، `type`؟، `value`؟، `maxDiscount`؟، `minAmount`؟، `validFrom`؟، `validTo`؟، `maxRedemptions`؟، `perUserLimit`؟، `firstOrderOnly`؟، `serviceIds`؟، `active`؟ |
| `QuoteDto` | `serviceId`، `promoCode`؟ |
| `RecordObservationsDto` | `observations`، `requestId`؟ |
| `ReferralClaimDto` | `code` |
| `RefreshDto` | `refreshToken`، `deviceId`؟ |
| `RegisterDto` | `phone`، `displayName`، `password` |
| `RejectDto` | `reason` |
| `ReleaseHoldDto` | `reason` |
| `ReportSosDto` | `clientEventId`، `sessionId`، `silent`، `expectedReporterId`، `triggeredAt` |
| `RetentionPolicyDto` | `pointDays`، `exportDays` |
| `ReviewAppealDto` | `status`، `reason` |
| `ReviewDto` | `stars`، `comment`؟، `punctualityStars`؟، `conductStars`؟، `clinicalStars`؟، `hygieneStars`؟، `overallStars`؟ |
| `RewardDto` | `nurseId`، `kind`، `amount`، `period`، `note`؟ |
| `SafeAbortDto` | `reason` |
| `SafetyCaseActionDto` | `clientActionId`، `expectedVersion`، `note`؟ |
| `SafetyCheckinResponseDto` | `checkinId`، `clientResponseId`، `response` |
| `SafetyLocationBatchDto` | `points` |
| `SafetyShiftDto` | `governorateId`؟، `shiftKind`، `primaryUserId`، `backupUserId`، `startsAt`، `endsAt` |
| `SavedPlaceDto` | `label`، `placeType`، `latitude`، `longitude`، `accuracy`، `formattedAddress`، `floor`؟، `building`؟، `landmark`؟، `notes`؟، `isDefault` |
| `SaveVisitNoteDto` | `servicesPerformed`، `clinicalNotes`، `materialsUsed`؟، `patientResponse`؟، `followupRecommendations`؟، `amendmentReason`؟، `isDraft`؟ |
| `SendMessageDto` | `content`، `clientMessageId`؟، `messageType`؟، `attachmentUrl`؟، `attachmentMeta`؟، `replyToMessageId`؟ |
| `ServiceDto` | `code`؟، `titleAr`؟، `descriptionAr`؟، `price`؟، `includedMinutes`؟، `blockMinutes`؟، `blockPrice`؟، `expectedMinutes`؟، `roundingStep`؟، `commissionBps`؟، `sortOrder`؟، `active`؟، `dispatchApproved`؟، `requiresPrescription`؟ |
| `SettingsDto` | `distanceEnabled`؟، `freeKm`؟، `perKm`؟، `maxDistanceFee`؟، `nightEnabled`؟، `nightStart`؟، `nightEnd`؟، `nightPercent`؟، `holidayEnabled`؟، `holidayPercent`؟، `weekendDays`؟، `stackSurcharges`؟، `taxEnabled`؟، `taxPercent`؟، `taxLabel`؟، `tipsEnabled`؟، `nurseDebtLimit`؟، `referralEnabled`؟، `referralReferredPercent`؟، `referralReferrerPercent`؟، `referralMaxDiscount`؟، `referralMaxRewardsPerMonth`؟، `promoAttemptsPerHour`؟، `promoMaxOrders30d`؟ |
| `SettleDto` | `direction`، `amount`، `note`؟ |
| `SkillsDto` | `serviceIds` |
| `StartSafetySessionDto` | `assignmentId` |
| `StatusDto` | `status` |
| `SubmitAppealDto` | `description` |
| `SubmitProposalDto` | `proposedArrivalAt`؟، `arrivalMinutes`؟، `note`؟ |
| `SwitchBookingModeDto` | `bookingMode`، `openDurationMinutes`؟، `latestAcceptableArrivalAt`؟، `scheduledAt`؟ |
| `TierDto` | `minReputation`؟، `minReviews`؟، `commissionBps`؟، `active`؟ |
| `TipDto` | `amount` |
| `TokenDto` | `token` |
| `TrustedContactDto` | `name`، `phone`، `relationship`، `priority`، `communication`، `requestLocation` |
| `UpdateAdminDto` | `displayName`؟، `phone`؟، `role`؟ |
| `UpdateNurseDto` | `phone`؟، `displayName`؟، `governorateId`؟، `areaId`؟، `specialty`؟، `nationalId`؟، `notes`؟، `nurseNo`؟ |
| `UpdatePreferencesInputDto` | `enablePush`؟، `enableInApp`؟، `enableSound`؟، `quietHoursEnabled`؟، `quietHoursStart`؟، `quietHoursEnd`؟، `mutedCategories`؟ |
| `UpdateServiceVisibilityDto` | `active`؟ |
| `UploadDto` | `kind`، `title`؟، `licenseRef`؟، `expiresAt`؟ |
| `VisitCompanionDto` | `nurseId`، `companionId` |
| `VisitRiskDto` | `decision`، `basis`، `reference`، `effectiveUntil` |
| `WithdrawProposalDto` | `reason`؟ |
