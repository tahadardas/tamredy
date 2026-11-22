# رفع تمريضي إلى Plesk — دليل المبتدئ من الصفر إلى النهاية

> **كل مرحلة فيها: ماذا تفعل ← ماذا يجب أن ترى.** إن اختلف ما تراه عن المكتوب فتوقف وانتقل إلى «حل المشاكل» في آخر الدليل أو أرسل لي لقطة الشاشة.
> رموز: 🖥️ على حاسوبك • 🌐 في متصفح Plesk • ⌨️ في الطرفية (Terminal) داخل Plesk.

## 0) ما تحتاجه قبل أن تبدأ
| الشيء | ملاحظة |
|---|---|
| خادم **VPS أو مخصص** (Linux) عليه Plesk | الاستضافة المشتركة لا تدعم Docker. إن كان خادمك Windows فأخبرني. |
| ذاكرة 4 GB ومساحة 10 GB على الأقل | البناء الأول يستهلك ذاكرة. |
| بيانات دخول Plesk (مدير/admin) | رابط الدخول عادة `https://عنوان-IP-الخادم:8443` |
| **نطاق** تملكه (مثلًا `example.com`) | سنُنشئ منه عنوانين: `api.example.com` و`admin.example.com` |
| مفتاح OpenRouteService | موجود عندك في `D:\Tamreedy\.env` (سطر `ORS_API_KEY=`) |
| (اختياري الآن) ملف مفتاح Firebase | `C:\Users\BIG\.tamreedy\fcm-service-account.json` |

---
## المرحلة 1 🖥️ — تجهيز حزمة الرفع على حاسوبك
1. افتح المجلد `D:\Tamreedy`.
2. **انقر مرتين** على الملف `1_make_server_bundle.bat`.
3. انتظر حتى تظهر عبارة `Done`. **المتوقع:** ملف جديد `D:\Tamreedy\deploy\tamreedy-server.tar.gz` (حجمه ≈ 1 MB).
4. اضغط أي زر لإغلاق النافذة.

---
## المرحلة 2 🌐 — الدخول إلى Plesk وتثبيت الإضافتين (Docker + SSH Terminal)
1. افتح المتصفح واكتب `https://عنوان-IP-الخادم:8443` (تجاهل تحذير الشهادة إن ظهر) وسجّل الدخول.
2. من القائمة اليسرى اختر **Extensions** (الإضافات) ← تبويب **Extensions Catalog** أو **My Extensions**.
3. في خانة البحث اكتب **Docker** ← اضغط **Install** (أو Get/Install) على إضافة *Docker* ← انتظر حتى تظهر «Installed».
4. كرر مع **SSH Terminal** (إن لم تجدها فابحث عن «SSH Terminal» أو «Web Terminal»).
   **المتوقع:** تظهر الإضافتان في **My Extensions**. إن لم تجد SSH Terminal فاستخدم برنامج PuTTY بدلًا منها (أخبرني).

---
## المرحلة 3 🌐 — إنشاء العنوانين الفرعيين
1. القائمة اليسرى: **Websites & Domains**.
2. تحت نطاقك اضغط **Add Subdomain**.
3. في «Subdomain name» اكتب `api` ← **OK**. **المتوقع:** يظهر `api.example.com` في القائمة.
4. كرر وأنشئ `admin` ← `admin.example.com`.
5. تأكد من أن سجلات DNS تعمل: اضغط **DNS Settings** للنطاق وتأكد أن سجل `api` و`admin` (نوع A) يشير إلى IP الخادم. (إن كان DNS عند شركة أخرى فأضف السجلين هناك.) قد يستغرق الانتشار من دقائق إلى ساعة.

---
## المرحلة 4 🌐 — رفع الحزمة إلى الخادم
1. **Websites & Domains** ← اختر النطاق الرئيسي `example.com` ← **Files** (مدير الملفات).
2. في أعلى القائمة اضغط **New** ← **Create Directory** ← اكتب `tamreedy` ← OK. (هذا المجلد ليس على الإنترنت لأنه خارج `httpdocs`؛ إن كان مدير الملفات يعرض `httpdocs` فقط فارجع خطوة للمجلد الأعلى.)
3. افتح المجلد `tamreedy` ← **Upload** ← اختر `D:\Tamreedy\deploy\tamreedy-server.tar.gz`.
   **المتوقع:** يظهر الملف داخل المجلد بحجم ≈ 1 MB.
4. إن كان ملف مفتاح Firebase جاهزًا فاترك رفعه لما بعد (المرحلة 8).

---
## المرحلة 5 ⌨️ — فتح الطرفية وفك الحزمة
1. **Tools & Settings** (الأدوات والإعدادات) ← **SSH Terminal** ← يفتح نافذة سوداء.
2. انسخ الأوامر التالية **سطرًا سطرًا** والصق (انقر يمين أو Ctrl+Shift+V) ثم Enter. **استبدل `example.com` باسم نطاقك**:
```bash
cd "$(dirname "$(find /var/www/vhosts -name tamreedy-server.tar.gz 2>/dev/null | head -1)")" && pwd
ls
```
**المتوقع:** يظهر `tamreedy-server.tar.gz`. ثم:
```bash
tar -xzf tamreedy-server.tar.gz
ls
```
**المتوقع:** تظهر مجلدات `apps` و`infra` وملفات `package.json`.
3. تأكد أن Docker يعمل:
```bash
docker --version && docker compose version
```
**المتوقع:** رقما إصدار. إن ظهر `command not found` فارجع للمرحلة 2 (تثبيت Docker) أو نفّذ: `curl -fsSL https://get.docker.com | sh`.

---
## المرحلة 6 ⌨️ — إعداد كلمات المرور والأسرار (مرة واحدة)
نفّذ **كل** هذه الأوامر معًا (تولّد كلمات سر عشوائية قوية وتحفظها في ملف خاص):
```bash
cd "$(dirname "$(find /var/www/vhosts -name tamreedy-server.tar.gz 2>/dev/null | head -1)")" && pwd
cp infra/docker/.env.prod.example infra/docker/.env
chmod 600 infra/docker/.env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" infra/docker/.env
```
ثم ضع مفتاح الخرائط (افتح `D:\Tamreedy\.env` على حاسوبك، انسخ القيمة بعد `ORS_API_KEY=` والصقها مكان `ضع_المفتاح_هنا`):
```bash
sed -i "s|^ORS_API_KEY=.*|ORS_API_KEY=ضع_المفتاح_هنا|" infra/docker/.env
```
تحقق (لا تُظهر الملف لأحد): `grep -c "=." infra/docker/.env` **المتوقع:** رقم 6 أو أكثر.

---
## المرحلة 7 ⌨️ — تشغيل النظام
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
```
- **أول مرة تستغرق 5–15 دقيقة** (تنزيل وبناء). لا تغلق النافذة. المتوقع في النهاية أسطر خضراء `Started/Healthy`.
- افحص الحالة:
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env ps
```
**المتوقع:** الخدمات `db` `redis` `api` `worker` `admin` بحالة **Up** (و`migrate` بحالة Exited (0) وهذا سليم).
- اختبر الخادم من الداخل:
```bash
curl -s http://127.0.0.1:3000/health
```
**المتوقع:** رد قصير بلا أخطاء.

**إنشاء أول مشرف** (غيّر الهاتف وكلمة المرور؛ 12 حرفًا على الأقل):
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env run --rm -e ADMIN_PHONE=+963XXXXXXXXX -e ADMIN_PASSWORD='ضع-كلمة-قوية-هنا' api node scripts/create-admin.mjs
```
**المتوقع:** `admin created: ...`.

**تفعيل كل ميزات التسويق والرسوم** (بقيم ابتدائية تعدّلها لاحقًا من اللوحة):
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env exec -T db psql -U tamreedy -d tamreedy < scripts/enable-all-features.sql
```

---
## المرحلة 8 (اختياري الآن) 🌐 — إشعارات Firebase
1. 🌐 مدير الملفات ← `tamreedy/infra/docker/secrets/` ← احذف الملف الفارغ `fcm.json` ← **Upload** ملف `C:\Users\BIG\.tamreedy\fcm-service-account.json` ← أعد تسميته إلى `fcm.json`.
2. ⌨️ أعد تشغيل العامل:
```bash
chmod 600 infra/docker/secrets/fcm.json
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env restart worker
```

---
## المرحلة 9 🌐 — ربط العنوانين بـHTTPS في Plesk
**كرر الخطوات لكل من `api.example.com` ثم `admin.example.com`:**
1. **Websites & Domains** ← افتح العنوان الفرعي ← **SSL/TLS Certificates**.
2. اضغط **Get it free** (أو Install) ← اترك «Secure the domain name» مفعّلة ← أدخل بريدك ← **Get it free**. **المتوقع:** «Certificate installed».
3. ارجع لبطاقة العنوان ← **Hosting & DNS** ← **Hosting** (أو Hosting Settings) ← فعّل **Permanent SEO-safe 301 redirect from HTTP to HTTPS** ← OK.
4. ارجع ← **Apache & nginx Settings**:
   - أوقف علامة **Proxy mode** و**Smart static files processing** إن وُجدتا.
   - في الصندوق **Additional nginx directives** الصق:

   لـ **api.example.com**:
```nginx
location / {
  proxy_pass http://127.0.0.1:3000;
  proxy_http_version 1.1;
  proxy_set_header Upgrade $http_upgrade;
  proxy_set_header Connection "upgrade";
  proxy_set_header Host $host;
  proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto $scheme;
  proxy_read_timeout 120s;
}
```
   ولـ **admin.example.com** نفس الكتلة لكن المنفذ **8080**: `proxy_pass http://127.0.0.1:8080;`
   - اضغط **OK**. (إن ظهر خطأ تعارض فاستبدل `location /` بـ `location ^~ /`.)

---
## المرحلة 10 — التحقق النهائي
1. في المتصفح افتح `https://api.example.com/health` ← **المتوقع:** رد سليم.
2. افتح `https://admin.example.com` ← تظهر لوحة تمريضي وأيقونتها في التبويب. اضغط أيقونة القابس أعلى الصفحة ← أدخل هاتف وكلمة مرور المشرف ← **دخول**.
3. من اللوحة: **الحسابات** ← أنشئ حساب ممرض وحساب مريض (تُعرض كلمة المرور المؤقتة مرة واحدة فاحتفظ بها).
4. **الخدمات والأسعار** ← أضف خدمة وفعّلها وأعتمدها سريريًا.

## المرحلة 11 🖥️ — بناء التطبيقين وتثبيتهما على الهاتف
في PowerShell داخل `D:\Tamreedy\apps\nurse_app` ثم `patient_app` (غيّر العنوان):
```powershell
flutter build apk --release --dart-define=DEMO=false --dart-define=API_BASE_URL=https://api.example.com --dart-define=FCM_ENABLED=true --dart-define=ANALYTICS_ENABLED=true
adb install -r build\app\outputs\flutter-apk\app-release.apk
```
سجّل الدخول بالحساب الذي أنشأته. جرّب: ممرض «متاح» + طلب من تطبيق المريض ← يرنّ هاتف الممرض.

## المرحلة 12 — نسخ احتياطي يومي (مهم)
🌐 **Tools & Settings** ← **Scheduled Tasks** ← **Add Task** ← النوع *Run a command* ← الأمر (بدّل example.com):
```bash
cd "$(dirname "$(find /var/www/vhosts -name tamreedy-server.tar.gz 2>/dev/null | head -1)")" && pwd && docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env exec -T db pg_dump -U tamreedy tamreedy | gzip > /var/backups/tamreedy-$(date +\%F).sql.gz
```
المستخدم: **root** • التكرار: **Daily 03:00** ← OK. انسخ ملفات `/var/backups` خارج الخادم أسبوعيًا.

## التحديث لاحقًا
كرّر المرحلة 1 والمرحلة 4 (رفع ملف جديد) ثم ⌨️:
```bash
cd "$(dirname "$(find /var/www/vhosts -name tamreedy-server.tar.gz 2>/dev/null | head -1)")" && pwd && tar -xzf tamreedy-server.tar.gz
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
```
(ملف `.env` والأسرار لا تُستبدل، والترحيلات تُطبَّق تلقائيًا.)

---
## حل المشاكل
| العَرَض | الحل |
|---|---|
| `docker: command not found` | ثبّت Docker من Extensions أو `curl -fsSL https://get.docker.com | sh` |
| أثناء البناء: `Killed` أو يتوقف | ذاكرة قليلة. أضف Swap: `fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile` ثم أعد أمر المرحلة 7 |
| `port is already allocated` | منفذ 3000/8080 مستخدم: افتح `infra/docker/.env` وغيّر `API_PORT`/`ADMIN_PORT` ثم غيّره في توجيه nginx |
| `502 Bad Gateway` على العنوان | الحاوية متوقفة: `docker compose ... ps` ثم `docker compose ... logs api` |
| `set POSTGRES_PASSWORD` | لم تنفّذ المرحلة 6 كاملة؛ أعدها |
| الصفحة تعرض شهادة غير آمنة | لم تصدر شهادة العنوان الفرعي بعد (المرحلة 9-2) أو DNS لم ينتشر |
| `migrate` يفشل | `docker compose ... logs migrate` وأرسل لي السطر الأخير |
| لا تصل الإشعارات | `fcm.json` فارغ؟ (المرحلة 8) وتأكد أن التطبيق بُني بـ`FCM_ENABLED=true` |
| لوحة التحكم لا تتصل | تأكد من توجيه `admin` إلى 8080 ومن أن `api` يعمل (`docker compose ... ps`) |

لا تشارك محتوى `infra/docker/.env` أو `fcm.json` مع أي أحد، بما فيهم أنا.

## ملحق: مستندات الممرضين والنسخ الاحتياطي
- الملفات المرفوعة (رخص/هويات) تُحفظ مشفّرة في وحدة التخزين `uploads` وتُقرأ فقط عبر لوحة الإدارة.
- ولّد مفتاح التشفير مرة واحدة وضعه في `.env`: `openssl rand -hex 32` ← `DOCS_ENC_KEY=...` واحتفظ بنسخة منه خارج الخادم. بدونه لا يمكن فك تشفير المستندات.
- النسخ الاحتياطي: قاعدة البيانات + وحدة `uploads` (`docker run --rm -v tamreedy_uploads:/d -v $PWD:/b alpine tar czf /b/uploads.tgz -C /d .`).
- بعد التحديث نفّذ البناء ثم `docker compose up -d`؛ ستُطبَّق الهجرة 009 تلقائيًا (رقم الممرض يبدأ من 1001).
