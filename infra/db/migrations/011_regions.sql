-- Governorates and areas (admin-managed; starts with Damascus and Rif Dimashq). Never deleted, only deactivated.
CREATE TABLE governorates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name_ar text NOT NULL UNIQUE,
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0
);
CREATE TABLE areas (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  governorate_id uuid NOT NULL REFERENCES governorates(id),
  name_ar text NOT NULL,
  active boolean NOT NULL DEFAULT true,
  sort_order integer NOT NULL DEFAULT 0,
  UNIQUE (governorate_id, name_ar)
);
ALTER TABLE nurses
  ADD COLUMN IF NOT EXISTS governorate_id uuid REFERENCES governorates(id),
  ADD COLUMN IF NOT EXISTS area_id uuid REFERENCES areas(id);
CREATE INDEX idx_nurses_region ON nurses (governorate_id, area_id);

INSERT INTO governorates(name_ar, sort_order) VALUES ('دمشق', 1), ('ريف دمشق', 2);
INSERT INTO areas(governorate_id, name_ar, sort_order)
SELECT g.id, a.name, a.ord FROM governorates g JOIN (VALUES
  ('دمشق','المزة',1),('دمشق','كفرسوسة',2),('دمشق','المالكي',3),('دمشق','أبو رمانة',4),('دمشق','الشعلان',5),('دمشق','المهاجرين',6),
  ('دمشق','ركن الدين',7),('دمشق','القصاع',8),('دمشق','باب توما',9),('دمشق','الميدان',10),('دمشق','القابون',11),('دمشق','برزة',12),
  ('دمشق','العدوي',13),('دمشق','الشاغور',14),('دمشق','دمر',15),('دمشق','التجارة',16),('دمشق','جوبر',17),('دمشق','القدم',18),
  ('دمشق','الصالحية',19),('دمشق','المزرعة',20),('دمشق','الحجاز',21),('دمشق','مشروع دمر',22),
  ('ريف دمشق','دوما',1),('ريف دمشق','حرستا',2),('ريف دمشق','عربين',3),('ريف دمشق','سقبا',4),('ريف دمشق','جرمانا',5),
  ('ريف دمشق','صحنايا',6),('ريف دمشق','أشرفية صحنايا',7),('ريف دمشق','داريا',8),('ريف دمشق','المعضمية',9),('ريف دمشق','قدسيا',10),
  ('ريف دمشق','الهامة',11),('ريف دمشق','التل',12),('ريف دمشق','قطنا',13),('ريف دمشق','الكسوة',14),('ريف دمشق','الزبداني',15),
  ('ريف دمشق','يبرود',16),('ريف دمشق','النبك',17),('ريف دمشق','دير عطية',18)
) AS a(gov, name, ord) ON a.gov = g.name_ar;
