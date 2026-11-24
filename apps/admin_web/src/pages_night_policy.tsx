import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {Chip, Notice, Panel, Table} from './ui';
import {Clock, Moon, RefreshCw, ShieldAlert} from 'lucide-react';

const path = '/v1/admin/safety/night-policy';
const modes = {
  ALLOW: 'السماح وفق الأهلية المعتادة',
  RESTRICT: 'منع العروض والزيارات خلال الفترة',
  REQUIRE_COVERAGE: 'اشتراط وجود تغطية سلامة نشطة',
  REQUIRE_OPT_IN_AND_COVERAGE: 'اشتراط الموافقة الصريحة وتغطية السلامة',
};
type Mode = keyof typeof modes;

type Rules = {
  enabled: boolean;
  rules: {
    id: string;
    mode: Mode;
    starts_at: string;
    ends_at: string;
    governorate_id: string | null;
    area_id: string | null;
    service_id: string | null;
  }[];
  regions: {id: string; name_ar: string}[];
  areas: {id: string; governorate_id: string; name_ar: string}[];
  services: {id: string; title_ar: string}[];
};

export function NightPolicy() {
  const [data, setData] = useState<Rules>();
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);
  const [mode, setMode] = useState<Mode>('REQUIRE_COVERAGE');
  const [from, setFrom] = useState('22:00');
  const [to, setTo] = useState('06:00');
  const [region, setRegion] = useState('');
  const [area, setArea] = useState('');
  const [service, setService] = useState('');

  async function load() {
    try {
      setData(await getJson(path));
      setError('');
    } catch (err) {
      setError(msgOf(err));
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await sendJson('POST', path, {
        mode,
        startsAt: from,
        endsAt: to,
        governorateId: region || undefined,
        areaId: area || undefined,
        serviceId: service || undefined,
      });
      await load();
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="night-policy-page">
      {error && (
        <div style={{marginBottom: 16}}>
          <Notice tone="danger">{error}</Notice>
        </div>
      )}

      {!data ? (
        <Panel title="سياسة العمل الليلي" subtitle="تحميل الإعدادات...">
          <button className="pill on" onClick={() => void load()}>
            تحميل سياسة العمل الليلي
          </button>
        </Panel>
      ) : (
        <>
          <div style={{marginBottom: 16}}>
            <Notice tone={data.enabled ? 'success' : 'warn'}>
              {data.enabled
                ? 'إنفاذ سياسة العمل الليلي نشط ومفعّل على السيرفر: يتم التحقق من شروط السلامة والتغطية عند إرسال العروض وقبولها.'
                : 'إنفاذ السياسة معطّل كسياسة إلزامية على السيرفر حالياً: يمكنك حفظ ومراجعة القواعد، وستُطبق فور تفعيل مفتاح السياسة الليلي.'}
            </Notice>
          </div>

          <Panel
            title="إضافة قاعدة ليلية جديدة"
            subtitle="تحديد أوقات وشروط قبول العروض والزيارات في الفترات المتأخرة لحماية الكوادر التمريضية"
            action={
              <button className="action-btn" onClick={() => void load()} title="تحديث البيانات">
                <RefreshCw size={15} />
                <span>تحديث</span>
              </button>
            }
          >
            <form onSubmit={save} className="form">
              <label>
                المحافظة
                <select
                  value={region}
                  onChange={e => {
                    setRegion(e.currentTarget.value);
                    setArea('');
                  }}
                >
                  <option value="">كافة المحافظات (تطبيق عام)</option>
                  {data.regions.map(r => (
                    <option key={r.id} value={r.id}>
                      {r.name_ar}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                المنطقة الجغرافية
                <select
                  value={area}
                  disabled={!region}
                  onChange={e => setArea(e.currentTarget.value)}
                >
                  <option value="">كافة المناطق</option>
                  {data.areas
                    .filter(a => a.governorate_id === region)
                    .map(a => (
                      <option key={a.id} value={a.id}>
                        {a.name_ar}
                      </option>
                    ))}
                </select>
              </label>

              <label>
                الخدمة التمريضية المشمولة
                <select value={service} onChange={e => setService(e.currentTarget.value)}>
                  <option value="">كافة الخدمات التمريضية</option>
                  {data.services.map(s => (
                    <option key={s.id} value={s.id}>
                      {s.title_ar}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                قاعدة الأهلية المطلوبة
                <select value={mode} onChange={e => setMode(e.currentTarget.value as Mode)}>
                  {Object.entries(modes).map(([id, label]) => (
                    <option key={id} value={id}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>

              <label>
                من الساعة (توقيت دمشق)
                <input
                  type="time"
                  required
                  value={from}
                  onChange={e => setFrom(e.currentTarget.value)}
                />
              </label>

              <label>
                إلى الساعة (توقيت دمشق)
                <input
                  type="time"
                  required
                  value={to}
                  onChange={e => setTo(e.currentTarget.value)}
                />
              </label>

              <div className="actions" style={{gridColumn: '1 / -1', marginTop: 8}}>
                <button className="pill on" type="submit" disabled={busy}>
                  + حفظ وتطبيق قاعدة السياسة الليلية
                </button>
              </div>
            </form>
          </Panel>

          <div style={{marginTop: 24}}>
            <Panel
              title="قواعد العمل الليلي المعتمدة"
              subtitle={`إجمالي القواعد المحددة: ${data.rules.length} قاعدة`}
            >
              {data.rules.length === 0 ? (
                <div className="empty-hint">لا توجد قواعد ليلية مخصصة حتى الآن. تطبق الإعدادات الافتراضية العامة للمنظومة.</div>
              ) : (
                <Table
                  head={['قاعدة الأهلية', 'الفترة الزمنية', 'المحافظة', 'المنطقة', 'الخدمة التمريضية']}
                  rows={data.rules.map(rule => {
                    const tone =
                      rule.mode === 'REQUIRE_COVERAGE'
                        ? 'warn'
                        : rule.mode === 'REQUIRE_OPT_IN_AND_COVERAGE'
                        ? 'purple'
                        : rule.mode === 'RESTRICT'
                        ? 'danger'
                        : 'success';

                    return [
                      <Chip key="mode" tone={tone}>
                        {modes[rule.mode]}
                      </Chip>,
                      <span key="time" dir="ltr" style={{fontWeight: 600, color: 'var(--navy)'}}>
                        {rule.starts_at.slice(0, 5)} - {rule.ends_at.slice(0, 5)}
                      </span>,
                      data.regions.find(r => r.id === rule.governorate_id)?.name_ar ?? 'كل المحافظات',
                      data.areas.find(a => a.id === rule.area_id)?.name_ar ?? 'كل المناطق',
                      data.services.find(s => s.id === rule.service_id)?.title_ar ?? 'كافة الخدمات',
                    ];
                  })}
                />
              )}
            </Panel>
          </div>
        </>
      )}
    </div>
  );
}
