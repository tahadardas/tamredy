# نشر الخادم على Plesk بواسطة Docker

يشغّل الحزمة كاملة: قاعدة بيانات **PostGIS** + **Redis** + **ترحيل القاعدة تلقائيًا** + **API** + **Worker** (التوزيع والإشعارات) + **لوحة التحكم**. لا يُنشر أي منفذ للإنترنت إلا عبر Plesk (HTTPS).

> **تنبيه صدق:** لا يتوفر Docker على جهاز التطوير، فلم تُبنَ الصور فعليًا هنا. حاكيتُ خطوات البناء نفسها (تثبيت مقفول، بناء، نشر بحزم الإنتاج فقط، تشغيل الناتج) فنجحت، لكن **أول بناء على خادمك قد يكشف مشكلة بيئية**؛ إن حدث فأرسل لي ناتج `docker compose logs`.

## 0) المتطلبات
- خادم Linux (VPS) عليه Plesk وصلاحية **root عبر SSH**، بذاكرة **4 GB** على الأقل (البناء يحتاج ≥ 2 GB) ومساحة 10 GB.
- **Docker + Compose plugin**: من Plesk ← Extensions ← «Docker»، أو عبر SSH:
  ```bash
  curl -fsSL https://get.docker.com | sh && docker compose version
  ```
- نطاقان فرعيان (سجلّا A يشيران إلى IP الخادم)، مثلًا: `api.example.com` للتطبيقات، و`admin.example.com` للوحة التحكم.

## 1) تجهيز الحزمة على حاسوبك
من جذر المشروع:
```powershell
powershell -ExecutionPolicy Bypass -File scripts\make-deploy-bundle.ps1
```
تنتج `deploy\tamreedy-server.tar.gz` (نحو 1 MB، بلا أسرار ولا node_modules).

## 2) الرفع والفك
```powershell
scp deploy\tamreedy-server.tar.gz root@SERVER_IP:/opt/
```
(أو ارفعها بمدير ملفات Plesk إلى أي مجلد ثم انقلها). ثم على الخادم:
```bash
mkdir -p /opt/tamreedy && tar -xzf /opt/tamreedy-server.tar.gz -C /opt/tamreedy && cd /opt/tamreedy
```

## 3) ملف الإعدادات (الأسرار)
```bash
cp infra/docker/.env.prod.example infra/docker/.env
chmod 600 infra/docker/.env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=$(openssl rand -hex 24)/" infra/docker/.env
sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$(openssl rand -hex 32)/" infra/docker/.env
nano infra/docker/.env      # ضع ORS_API_KEY (مفتاح OpenRouteService) وراجع بقية القيم
```
> استخدم كلمات مرور سداسية عشرية فقط (كما أعلاه) لأنها تدخل داخل روابط الاتصال.

**الإشعارات (اختياري الآن):** انسخ ملف مفتاح حساب خدمة Firebase إلى `infra/docker/secrets/fcm.json` (`chmod 600`). الملف الفارغ الموجود = الإشعارات معطّلة.

## 4) التشغيل
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env ps
```
المتوقع: `db` و`redis` و`api` و`worker` و`admin` تعمل، و`migrate` انتهى بنجاح (Exited 0). للسجلات:
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env logs -f api worker
curl -s http://127.0.0.1:3000/health
```

## 5) أول مشرف (مرة واحدة)
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env run --rm \
  -e ADMIN_PHONE=+963XXXXXXXXX -e ADMIN_PASSWORD='كلمة-قوية-12-حرفًا-على-الأقل' api node scripts/create-admin.mjs
```

## 6) ربط النطاقات وHTTPS في Plesk
لكل نطاق فرعي: **Websites & Domains ← Add Subdomain** ثم:
1. **SSL/TLS Certificates** أو **Let's Encrypt** ← أصدر شهادة وفعّل «Redirect HTTP to HTTPS».
2. **Apache & nginx Settings**: أوقف «Proxy mode» و«Smart static files processing» إن ظهرا، ثم في **Additional nginx directives** ضع:

**`api.example.com`** (التطبيقات + WebSocket) → المنفذ 3000:
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
**`admin.example.com`** (لوحة التحكم) → المنفذ 8080: نفس الكتلة مع `proxy_pass http://127.0.0.1:8080;`.

> إن ظهر تعارض مع `location /` الافتراضي لـPlesk فاستبدلها بـ`location ^~ /`.

## 7) الاختبار
- `https://api.example.com/health` ← يجب أن يعيد حالة سليمة.
- `https://admin.example.com` ← سجّل الدخول بحساب المشرف (أيقونة الاتصال أعلى الصفحة).
- ابنِ التطبيقين على حاسوبك:
```powershell
flutter build apk --dart-define=DEMO=false --dart-define=API_BASE_URL=https://api.example.com `
  --dart-define=FCM_ENABLED=true --dart-define=ANALYTICS_ENABLED=true
```

## 8) التحديث
أنشئ حزمة جديدة (الخطوة 1)، ارفعها، فُكّها فوق المجلد نفسه (`tar -xzf ... -C /opt/tamreedy`)، ثم أعد الأمر في الخطوة 4. الترحيلات تُطبَّق تلقائيًا ولا تمس البيانات؛ ملف `.env` والمفاتيح لا تُستبدل.

## 9) النسخ الاحتياطي (أساسي)
```bash
# يوميًا الساعة 3 صباحًا عبر Plesk ← Scheduled Tasks
docker compose -f /opt/tamreedy/infra/docker/docker-compose.prod.yml --env-file /opt/tamreedy/infra/docker/.env \
  exec -T db pg_dump -U tamreedy tamreedy | gzip > /var/backups/tamreedy-$(date +\%F).sql.gz
```
انسخ النسخ خارج الخادم. الاستعادة: `gunzip -c ملف.sql.gz | docker compose ... exec -T db psql -U tamreedy tamreedy`.

## 10) قائمة الأمان قبل استقبال مستخدمين
- [ ] HTTPS فعّال على النطاقين، وجدار الحماية يفتح 80/443/22 فقط (قاعدة البيانات وRedis غير منشورين أصلًا).
- [ ] `infra/docker/.env` بصلاحية 600 ولا يغادر الخادم.
- [ ] **لوحة التحكم تحمي كل شيء ودخول المشرف بكلمة مرور فقط** (لا MFA بعد): قيّد الوصول إلى `admin.example.com` بعناوين IP موثوقة (Plesk ← IP Address Restriction) إلى أن تُبنى المصادقة الثنائية.
- [ ] نسخ احتياطي يومي خارج الخادم، واختبر الاستعادة مرة.
- [ ] لا تستخدم بيانات مرضى حقيقية قبل الترخيص والمراجعة القانونية والسريرية (انظر `docs/SECURITY_AND_GAPS_AR.md`).

## إيقاف/تشغيل
```bash
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env restart api worker
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env down     # إيقاف (البيانات تبقى في الأحجام)
```
