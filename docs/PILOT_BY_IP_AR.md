# تجربة بلدة صغيرة بدون دومين (عبر IP الخادم)

خادمك: `85.215.243.237` • المنفذ الخارجي للـAPI: **18300** • للوحة التحكم: **18380** (بدل 3000 و8080 المحجوزين).
لوحة التحكم: `http://85.215.243.237:18380` • الـAPI: `http://85.215.243.237:18300/health`

> ⚠️ **بدون دومين لا يوجد HTTPS**، أي أن كلمات المرور تسافر غير مشفّرة. هذا مقبول **لتجربة صغيرة ببيانات اختبارية فقط** وبكلمات مرور مؤقتة. لا تُدخل بيانات مرضى حقيقية، ولا كلمة مرور تستخدمها في مكان آخر. قبل الإطلاق الحقيقي اشترِ دومينًا ونفّذ دليل HTTPS (`PLESK_STEP_BY_STEP_AR.md` المرحلة 9).
> العنوان الفرعي `tamredy.dardus.com.sy` الذي أنشأتَه لا يُحَلّ على الإنترنت الآن، **تجاهله** (لا تحذفه إن لم تكن متأكدًا، لا يضر).

## قبل أن تبدأ: تأكد أن المنفذين حرّان
في **SSH Terminal**:
```bash
ss -ltnp | grep -E ':(18300|18380)\b' || echo "المنفذان حرّان"
```
إن ظهر سطر فهما مستخدمان؛ اختر رقمين آخرين (مثل 18301 و18381) وعدّل `API_PORT` و`ADMIN_PORT` في الملف `.env` أدناه، ثم أعد بناء التطبيقين بالمنفذ الجديد (أخبرني).

## الخطوات (مختصرة؛ التفاصيل في PLESK_STEP_BY_STEP_AR.md المراحل 1–7)
1. 🖥️ انقر مرتين `1_make_server_bundle.bat` ← ملف `deploy\tamreedy-server.tar.gz`.
2. 🌐 Plesk ← **Websites & Domains** ← `tamredy.dardus.com.sy` ← **Files** ← أنشئ مجلد `tamreedy` ← ارفع الملف.
3. ⌨️ SSH Terminal (اضغط بطاقة **SSH Terminal** في صفحة الاشتراك كما في لقطتك):
```bash
cd "$(dirname "$(find /var/www/vhosts -name tamreedy-server.tar.gz 2>/dev/null | head -1)")" && pwd
tar -xzf tamreedy-server.tar.gz
cp infra/docker/.env.prod.example infra/docker/.env
chmod 600 infra/docker/.env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" infra/docker/.env
sed -i "s|^ORS_API_KEY=.*|ORS_API_KEY=ضع_المفتاح_هنا|" infra/docker/.env
# فتح المنفذين للإنترنت (بدون دومين):
sed -i "s/^API_BIND=.*/API_BIND=0.0.0.0/; s/^ADMIN_BIND=.*/ADMIN_BIND=0.0.0.0/" infra/docker/.env
```
(مفتاح الخرائط: انسخه من `D:\Tamreedy\.env` بعد `ORS_API_KEY=` وبدّله مكان `ضع_المفتاح_هنا`.)
4. ⌨️ التشغيل:
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env ps
```
5. ⌨️ أول مشرف + تفعيل الميزات:
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env run --rm -e ADMIN_PHONE=+963XXXXXXXXX -e ADMIN_PASSWORD='كلمة-مؤقتة-12-حرفًا' api node scripts/create-admin.mjs
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env exec -T db psql -U tamreedy -d tamreedy < scripts/enable-all-features.sql
```

## فتح المنفذين في الجدار الناري (مهم، وإلا لن يتصل أحد)
1. 🌐 Plesk ← **Tools & Settings** ← **Firewall** (إن لم يظهر فثبّت إضافة *Plesk Firewall* من Extensions) ← **Modify Plesk Firewall Rules** ← **Add Custom Rule**:
   - Name: `Tamreedy API` • Direction: Incoming • Action: Allow • Ports: **TCP 18300** ← OK
   - أضف قاعدة ثانية: `Tamreedy Admin` • **TCP 18380**
   - اضغط **Apply Changes**.
2. إن كان الخادم عند شركة استضافة لها **جدار ناري سحابي** (مثل IONOS: Network ← Firewall Policies) فافتح المنفذين هناك أيضًا.
3. اختبر من متصفح الهاتف (بيانات الجوال لا الواي فاي): `http://85.215.243.237:18300/health`.

## الدخول والتجربة
- 🌐 `http://85.215.243.237:18380` ← أيقونة القابس ← هاتف وكلمة مرور المشرف.
- **الحسابات**: أنشئ حسابات الممرضين والمرضى التجريبيين، **الخدمات والأسعار**: أضف الخدمات واعتمدها.
- 🖥️📱 التطبيقان الجاهزان بعنوان خادمك: `D:\Tamreedy\deploy\apk\tamreedy-nurse-pilot.apk` و`tamreedy-patient-pilot.apk`. ثبّتهما على الهواتف (انسخ الملف للهاتف وافتحه، فعّل «التثبيت من مصادر غير معروفة» إن طُلب) أو من الحاسوب: `adb install -r الملف.apk`.
  (التطبيقان مضبوطان للسماح بـHTTP لهذا الـIP فقط.)

## أمان الحد الأدنى للتجربة
- كلمات مرور مؤقتة، ولا بيانات حقيقية.
- اجعل لوحة التحكم مقيّدة: في Plesk Firewall أضف قاعدة للمنفذ 18380 تسمح لعنوان IP الذي تعمل منه فقط (إن كان ثابتًا).
- بعد انتهاء التجربة: `docker compose ... down` أو أغلق قواعد الجدار الناري.
- نسخة احتياطية قبل أي تحديث (انظر الدليل الكامل المرحلة 12).

## الانتقال لاحقًا إلى دومين
1. اشترِ دومينًا ووجّه `api` و`admin` إلى IP الخادم.
2. نفّذ المرحلة 9 (HTTPS + nginx) واجعل `API_BIND=127.0.0.1` و`ADMIN_BIND=127.0.0.1` في `.env`.
3. احذف كتلة `<domain-config>` من `network_security_config.xml` في التطبيقين وأعد بناءهما بالعنوان `https://api.نطاقك`.
