-- Baseline medical services catalog seed
-- Safe and idempotent: ON CONFLICT (code) DO NOTHING preserves existing records and any admin pricing modifications.

INSERT INTO services(
  code,
  title_ar,
  description_ar,
  active,
  dispatch_approved,
  requires_prescription,
  price_amount,
  currency_code,
  commission_bps,
  included_minutes,
  block_minutes,
  block_price,
  expected_minutes,
  sort_order
)
VALUES
  ('INJ_IM_IV', 'حقن وعلاجات وريدية وعضلية', 'إعطاء حقن عضلية أو وريدية وتركيب سيرومات وفق وصفة طبية معتمدة', true, true, true, 25000, 'SYP_NEW', 2000, 30, 15, 5000, 30, 1),
  ('WOUND_CARE', 'تضميد جروح وقرحات سريرية', 'تنظيف وتطهير الجروح السطحية والعميقة وتغيير الضمادات المعقمة', true, true, false, 35000, 'SYP_NEW', 2000, 45, 15, 5000, 45, 2),
  ('URINARY_CATHETER', 'تركيب واستبدال قثطرة بولية', 'تركيب أو تبديل القثطرة البولية مع العناية والتعقيم الطبي الكامل', true, true, true, 40000, 'SYP_NEW', 2000, 40, 15, 6000, 40, 3),
  ('VITAL_SIGNS', 'قياس العلامات الحيوية وفحص سكر', 'فحص الضغط والنبض والحرارة ونسبة الأكسجين ومستوى السكر في الدم', true, true, false, 15000, 'SYP_NEW', 2000, 20, 15, 3000, 20, 4),
  ('BLOOD_SAMPLE', 'سحب عينات دم وتحاليل مخبرية', 'سحب عينات الدم المخبرية بعناية وحفظها لنقلها للمختبر المعتمد', true, true, true, 20000, 'SYP_NEW', 2000, 25, 15, 4000, 25, 5),
  ('ELDERLY_NURSING', 'رعاية تمريضية منزلية شاملة', 'عناية تمريضية بالمرضى وكبار السن وإعطاء الأدوية المقررة والمتابعة', true, true, false, 50000, 'SYP_NEW', 2000, 60, 15, 8000, 60, 6)
ON CONFLICT (code) DO NOTHING;
