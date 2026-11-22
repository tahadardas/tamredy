-- Seed initial active clinical services for patient and nurse apps
INSERT INTO services(code, title_ar, description_ar, active, dispatch_approved, requires_prescription, price_amount, currency_code, commission_bps, included_minutes, block_minutes, block_price, expected_minutes)
VALUES
  ('inj_im_iv', 'حقن وعلاجات وريدية وعضلية', 'إعطاء حقن عضلية أو وريدية وتركيب سيرومات وفق وصفة طبية معتمدة', true, true, true, 25000, 'SYP_NEW', 2000, 30, 15, 5000, 30),
  ('wound_care', 'تضميد جروح وقرحات سريرية', 'تنظيف وتطهير الجروح السطحية والعميقة وتغيير الضمادات المعقمة', true, true, false, 35000, 'SYP_NEW', 2000, 45, 15, 5000, 45),
  ('urinary_catheter', 'تركيب واستبدال قثطرة بولية', 'تركيب أو تبديل القثطرة البولية مع العناية والتعقيم الطبي الكامل', true, true, true, 40000, 'SYP_NEW', 2000, 40, 15, 6000, 40),
  ('vital_signs', 'قياس العلامات الحيوية وفحص سكر', 'فحص الضغط والنبض والحرارة ونسبة الأكسجين ومستوى السكر في الدم', true, true, false, 15000, 'SYP_NEW', 2000, 20, 15, 3000, 20),
  ('blood_sample', 'سحب عينات دم وتحاليل مخبرية', 'سحب عينات الدم المخبرية بعناية وحفظها لنقلها للمختبر المعتمد', true, true, true, 20000, 'SYP_NEW', 2000, 25, 15, 4000, 25),
  ('elderly_nursing', 'رعاية تمريضية منزلية شاملة', 'عناية تمريضية بالمرضى وكبار السن وإعطاء الأدوية المقررة والمتابعة', true, true, false, 50000, 'SYP_NEW', 2000, 60, 15, 8000, 60)
ON CONFLICT (code) DO UPDATE SET
  title_ar = EXCLUDED.title_ar,
  description_ar = EXCLUDED.description_ar,
  active = true,
  dispatch_approved = true,
  price_amount = EXCLUDED.price_amount;
