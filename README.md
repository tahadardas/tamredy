# Tamreedy (تمريضي) — Home Healthcare & Nursing On-Demand Platform

منظومة **تمريضي** المتكاملة لخدمات الرعاية التمريضية والطبية المنزلية عند الطلب.

---

## 🏛️ Architecture & Components (هيكلية المنظومة)

- **`apps/patient_app`**: تطبيق المريض (Flutter) لطلب الخدمات التمريضية وتحديد الموقع الجغرافي وتتبع مسار الممرض.
- **`apps/nurse_app`**: تطبيق الممرض (Flutter) لاستقبال عروض الزيارات، قبول الطلبات، الملاحة، وإدارة الأرباح وساعات العمل.
- **`packages/flutter_core`**: حزمة مكتبية مشتركة لـ Flutter تضم نظام التصميم الطبي، العميل البرمجي للـ API، المصادقة، وإشعارات FCM اللحظية.
- **`apps/api`**: خادم الـ API الخلفي مبني باستخدام NestJS، يدعم المصادقة الموثوقة (JWT)، التوزيع اللحظي، وإدارة الطلبات والكوادر.
- **`apps/worker`**: خدمة المعالجة الميدانية ومحرك التوزيع الجغرافي (Dispatch Engine) على دفعات وموجات (Wave-based Candidate Selection).
- **`apps/admin_web`**: لوحة تحكم إدارية وطبية متطورة (React + Vite) لإدارة العمليات الميدانية، اعتماد الكوادر والوثائق، والمالية والرسوم.
- **`infra`**: إعدادات البنية التحتية، ملفات Docker Compose للإنتاج، ومخططات قاعدة البيانات وترقياتها (PostgreSQL / PostGIS Migrations 001 - 014).
- **`docs`**: التوثيق التقني، سجلات القرارات المعمارية (ADRs)، وأدلة النشر والتشغيل.
- **`scripts`**: أدوات التشغيل الآلي، تهيئة الخدمات، وترقية قواعد البيانات.

---

## 🚀 Quick Start (التشغيل السريع)

### Server (Docker):
```bash
cp infra/docker/.env.prod.example infra/docker/.env
# Edit your database passwords and API keys in infra/docker/.env
docker compose -f infra/docker/docker-compose.prod.yml --env-file infra/docker/.env up -d --build
```

### Mobile Apps (Flutter):
```bash
# Patient App
cd apps/patient_app
flutter pub get
flutter run

# Nurse App
cd apps/nurse_app
flutter pub get
flutter run
```

---

## 📄 Documentation (التوثيق)
راجع مجلد `docs/` للاطلاع على أدلة التشغيل والقرارات الهندسية التفصيلية:
- `docs/ADR_INDEX.md`
- `docs/PLESK_STEP_BY_STEP_AR.md`
