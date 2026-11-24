-- Migration 042: Advanced Medical Catalog, Categories, and Multi-Service Items

CREATE TABLE IF NOT EXISTS service_categories (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  title_ar text NOT NULL,
  title_en text NOT NULL,
  description_ar text,
  icon text,
  sort_order integer NOT NULL DEFAULT 0,
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- Extend services with advanced clinical, scheduling and pricing metadata
ALTER TABLE services
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES service_categories(id),
  ADD COLUMN IF NOT EXISTS title_en text,
  ADD COLUMN IF NOT EXISTS icon text,
  ADD COLUMN IF NOT EXISTS requires_clinical_review boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS required_skills text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS required_credentials text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS consumables_included boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS night_availability boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS scheduling_allowed boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS recurring_visits_allowed boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS risk_classification text NOT NULL DEFAULT 'LOW' CHECK (risk_classification IN ('LOW','MEDIUM','HIGH')),
  ADD COLUMN IF NOT EXISTS additional_block_price numeric(18,2) DEFAULT 0 CHECK (additional_block_price >= 0);

-- Multi-service items per care request
CREATE TABLE IF NOT EXISTS care_request_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id uuid NOT NULL REFERENCES care_requests(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES services(id),
  quantity integer NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price numeric(18,2) NOT NULL CHECK (unit_price >= 0),
  expected_minutes integer NOT NULL DEFAULT 30 CHECK (expected_minutes > 0),
  pricing_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  clinical_requirements_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  item_status text NOT NULL DEFAULT 'PENDING' CHECK (item_status IN ('PENDING','COMPLETED','SKIPPED','CANCELLED')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_care_request_items_request ON care_request_items(request_id);
CREATE INDEX IF NOT EXISTS idx_care_request_items_service ON care_request_items(service_id);
CREATE INDEX IF NOT EXISTS idx_services_category ON services(category_id);

-- Seed Categories
INSERT INTO service_categories (code, title_ar, title_en, description_ar, icon, sort_order)
VALUES
  ('INJECTIONS_TREATMENTS', 'الحقن والعلاجات', 'Injections & Treatments', 'إعطاء الحقن الوريدية والعضلية والمحاليل الطبية وفق الوصفات المعتمدة', 'syringe', 1),
  ('WOUNDS_DRESSINGS', 'الجروح والضمادات', 'Wounds & Dressings', 'العناية بالضمادات والجروح الجراحية والمزمنة وقرحات الضغط والتعقيم الطبي', 'bandage', 2),
  ('MEASUREMENTS_SAMPLES', 'القياسات والعينات', 'Measurements & Samples', 'قياس العلامات الحيوية وسكر الدم وسحب العينات المخبرية ونقلها الآمن', 'activity', 3),
  ('CATHETERS_RESPIRATORY', 'القساطر والرعاية التنفسية', 'Catheters & Respiratory Care', 'تركيب واستبدال القساطر البولية وجلسات الرذاذ ومتابعة الأكسجين', 'lungs', 4),
  ('HOME_CARE', 'الرعاية المنزلية', 'Home Nursing Care', 'رعاية كبار السن ومتابعة الحالات المزمنة والرعاية بعد العمليات الجراحية بالساعة', 'home_plus', 5)
ON CONFLICT (code) DO UPDATE SET
  title_ar = EXCLUDED.title_ar,
  title_en = EXCLUDED.title_en,
  description_ar = EXCLUDED.description_ar,
  icon = EXCLUDED.icon,
  sort_order = EXCLUDED.sort_order;

-- Link baseline services to categories
UPDATE services SET category_id = (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS')
WHERE code = 'INJ_IM_IV' AND category_id IS NULL;

UPDATE services SET category_id = (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS')
WHERE code = 'WOUND_CARE' AND category_id IS NULL;

UPDATE services SET category_id = (SELECT id FROM service_categories WHERE code = 'CATHETERS_RESPIRATORY')
WHERE code = 'URINARY_CATHETER' AND category_id IS NULL;

UPDATE services SET category_id = (SELECT id FROM service_categories WHERE code = 'MEASUREMENTS_SAMPLES')
WHERE code IN ('VITAL_SIGNS', 'BLOOD_SAMPLE') AND category_id IS NULL;

UPDATE services SET category_id = (SELECT id FROM service_categories WHERE code = 'HOME_CARE')
WHERE code = 'ELDERLY_NURSING' AND category_id IS NULL;

-- Seed Advanced Detailed Subcategory Services
INSERT INTO services (
  code, category_id, title_ar, title_en, description_ar, active, dispatch_approved,
  requires_prescription, requires_clinical_review, price_amount, currency_code, commission_bps,
  included_minutes, block_minutes, block_price, expected_minutes, sort_order,
  consumables_included, night_availability, scheduling_allowed, recurring_visits_allowed, risk_classification
)
VALUES
  -- 1. Injections & Treatments
  ('INJ_IM', (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS'),
   'حقن عضلي', 'Intramuscular Injection', 'إعطاء حقنة عضلية معقمة وفق وصفة طبية', true, true,
   true, false, 20000, 'SYP_NEW', 2000, 20, 15, 4000, 20, 10, true, true, true, true, 'LOW'),
  ('INJ_SC', (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS'),
   'حقن تحت الجلد', 'Subcutaneous Injection', 'إعطاء حقن الأنسولين أو مضادات التخثر تحت الجلد', true, true,
   true, false, 18000, 'SYP_NEW', 2000, 20, 15, 3500, 20, 11, true, true, true, true, 'LOW'),
  ('IV_CANNULA_INSERT', (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS'),
   'تركيب قنية وريدية', 'IV Cannula Insertion', 'تركيب قنية وريدية محيطية معقمة وتثبيتها الآمن', true, true,
   true, false, 25000, 'SYP_NEW', 2000, 25, 15, 5000, 25, 12, true, true, true, true, 'MEDIUM'),
  ('IV_INFUSION', (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS'),
   'إعطاء محاليل وريدية', 'IV Infusion Therapy', 'إعطاء المحاليل الوريدية ومراقبة معدل التدفق والعلامات الحيوية', true, true,
   true, true, 30000, 'SYP_NEW', 2000, 45, 15, 6000, 45, 13, true, true, true, true, 'MEDIUM'),
  ('IV_CANNULA_REMOVE', (SELECT id FROM service_categories WHERE code = 'INJECTIONS_TREATMENTS'),
   'إزالة القنية الوريدية', 'IV Cannula Removal', 'إزالة القنية الوريدية وتطهير موضع الحقن وتضميده', true, true,
   false, false, 12000, 'SYP_NEW', 2000, 15, 15, 2500, 15, 14, true, true, true, false, 'LOW'),

  -- 2. Wounds & Dressings
  ('WOUND_SIMPLE_DRESSING', (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS'),
   'تبديل ضماد بسيط', 'Simple Wound Dressing', 'تطهير الجروح البسيطة السطحية وتبديل الضماد المعقم', true, true,
   false, false, 25000, 'SYP_NEW', 2000, 25, 15, 4500, 25, 20, true, true, true, true, 'LOW'),
  ('WOUND_POST_OP', (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS'),
   'متابعة جروح العمليات', 'Post-Op Wound Care', 'متابعة جرح العمليات الجراحية والتحقق من علامات الالتئام والعدوى', true, true,
   true, true, 35000, 'SYP_NEW', 2000, 35, 15, 6000, 35, 21, true, true, true, true, 'MEDIUM'),
  ('WOUND_PRESSURE_ULCER', (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS'),
   'العناية بقرحات الضغط', 'Pressure Ulcer Care', 'تنظيف وتضميد قرحات الفراش والضغط بمواد طبية متخصصة', true, true,
   true, true, 45000, 'SYP_NEW', 2000, 50, 15, 8000, 50, 22, true, true, true, true, 'HIGH'),
  ('SUTURE_REMOVAL', (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS'),
   'إزالة الغرز الجراحية', 'Suture Removal', 'إزالة القطب أو الغرز الجراحية بأدوات معقمة ذات استخدام واحد', true, true,
   true, false, 30000, 'SYP_NEW', 2000, 30, 15, 5000, 30, 23, true, false, true, false, 'MEDIUM'),
  ('STOMA_CARE', (SELECT id FROM service_categories WHERE code = 'WOUNDS_DRESSINGS'),
   'العناية بموضع الفغرة الطبية', 'Stoma & Ostomy Care', 'تنظيف الفغرة وتغيير كيس الفغرة وتقديم الإرشادات التمريضية للمريض', true, true,
   false, false, 35000, 'SYP_NEW', 2000, 35, 15, 6000, 35, 24, true, true, true, true, 'MEDIUM'),

  -- 3. Measurements & Samples
  ('BP_GLUCOSE_CHECK', (SELECT id FROM service_categories WHERE code = 'MEASUREMENTS_SAMPLES'),
   'قياس الضغط والسكر', 'BP & Blood Glucose Check', 'قياس ضغط الدم ومستوى السكر وتوثيق القراءات مع الاستشارة الأولية', true, true,
   false, false, 15000, 'SYP_NEW', 2000, 15, 15, 3000, 15, 30, true, true, true, true, 'LOW'),
  ('ECG_RECORDING', (SELECT id FROM service_categories WHERE code = 'MEASUREMENTS_SAMPLES'),
   'تخطيط القلب الكهربائي المنزلي', 'Home ECG Recording', 'إجراء تخطيط القلب بـ 12 مسرى بجهاز محمول وإرسال التقرير للمختص', true, true,
   true, true, 60000, 'SYP_NEW', 2000, 40, 15, 10000, 40, 31, true, false, true, false, 'MEDIUM'),

  -- 4. Catheters & Respiratory
  ('NEBULIZER_SESSION', (SELECT id FROM service_categories WHERE code = 'CATHETERS_RESPIRATORY'),
   'جلسة رذاذ تنفسي (إرذاذ)', 'Nebulizer Therapy Session', 'إعطاء جلسة الرذاذ بالأدوية الموصوفة ومراقبة التنفس ونسبة الأكسجين', true, true,
   true, false, 20000, 'SYP_NEW', 2000, 30, 15, 4000, 30, 40, true, true, true, true, 'LOW'),
  ('URINARY_CATHETER_CARE', (SELECT id FROM service_categories WHERE code = 'CATHETERS_RESPIRATORY'),
   'العناية بالقسطرة البولية وغسيلها', 'Catheter Care & Irrigation', 'تفريغ وتطهير كيس جمع البول والعناية بموضع القسطرة لمنع الإنتان', true, true,
   false, false, 25000, 'SYP_NEW', 2000, 30, 15, 4500, 30, 41, true, true, true, true, 'MEDIUM'),

  -- 5. Home Care
  ('HOURLY_NURSING_CARE', (SELECT id FROM service_categories WHERE code = 'HOME_CARE'),
   'رعاية تمريضية بالساعة (3 ساعات)', 'Hourly Home Nursing (3h)', 'رعاية تمريضية مكثفة للمريض ومتابعة العلامات الحيوية وإعطاء العلاج ومساعدة الحركة', true, true,
   false, false, 120000, 'SYP_NEW', 2000, 180, 60, 35000, 180, 50, true, true, true, true, 'MEDIUM'),
  ('CHRONIC_CARE_VISIT', (SELECT id FROM service_categories WHERE code = 'HOME_CARE'),
   'متابعة الحالات المزمنة الدورية', 'Chronic Care Follow-up', 'تقييم تمريضي دوري لمرضى السكري والضغط والقلب وجرد الأدوية اليومية', true, true,
   false, false, 35000, 'SYP_NEW', 2000, 45, 15, 7000, 45, 51, true, true, true, true, 'LOW')
ON CONFLICT (code) DO NOTHING;
