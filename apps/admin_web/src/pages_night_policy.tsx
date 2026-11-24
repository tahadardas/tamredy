import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';

const path = '/v1/admin/safety/night-policy';
const modes = {
  ALLOW: 'السماح وفق الأهلية المعتادة',
  RESTRICT: 'منع العروض خلال الفترة',
  REQUIRE_COVERAGE: 'اشتراط وجود تغطية سلامة',
  REQUIRE_OPT_IN_AND_COVERAGE: 'اشتراط الموافقة الصريحة والتغطية',
};
type Mode = keyof typeof modes;
type Rules = {
  enabled: boolean;
  rules: { id: string; mode: Mode; starts_at: string; ends_at: string; governorate_id: string | null; area_id: string | null; service_id: string | null }[];
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
    try { setData(await getJson(path)); setError(''); }
    catch (error) { setError(msgOf(error)); }
  }

  useEffect(() => { void load(); }, []);

  async function save(event: FormEvent) {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    try {
      await sendJson('POST', path, {
        mode, startsAt: from, endsAt: to, governorateId: region || undefined,
        areaId: area || undefined, serviceId: service || undefined,
      });
      await load();
    } catch (error) {
      setError(msgOf(error));
    } finally {
      setBusy(false);
    }
  }

  return <section className="card">
    {error && <p role="alert">{error}</p>}
    {!data ? <button className="pill" onClick={() => void load()}>تحميل سياسة العمل الليلي</button> : <>
      <p>{data.enabled ? 'تُطبّق السياسة عند إرسال العروض وقبولها.' : 'إنفاذ السياسة معطّل على الخادم. تُحفظ الإصدارات للمراجعة.'}</p>
      <form onSubmit={save}>
        <fieldset disabled={busy}>
          <legend>حفظ إصدار جديد</legend>
          <label>محافظة الكادر <select value={region} onChange={e => {setRegion(e.currentTarget.value); setArea('');}}>
            <option value="">الكل</option>{data.regions.map(r => <option key={r.id} value={r.id}>{r.name_ar}</option>)}
          </select></label>
          <label>منطقة الكادر <select value={area} disabled={!region} onChange={e => setArea(e.currentTarget.value)}>
            <option value="">الكل</option>{data.areas.filter(a => a.governorate_id === region).map(a => <option key={a.id} value={a.id}>{a.name_ar}</option>)}
          </select></label>
          <label>الخدمة <select value={service} onChange={e => setService(e.currentTarget.value)}>
            <option value="">الكل</option>{data.services.map(s => <option key={s.id} value={s.id}>{s.title_ar}</option>)}
          </select></label>
          <label>قاعدة الأهلية <select value={mode} onChange={e => setMode(e.currentTarget.value as Mode)}>
            {Object.entries(modes).map(([id,label]) => <option key={id} value={id}>{label}</option>)}
          </select></label>
          <label>من (توقيت دمشق) <input type="time" required value={from} onChange={e => setFrom(e.currentTarget.value)} /></label>
          <label>إلى (توقيت دمشق) <input type="time" required value={to} onChange={e => setTo(e.currentTarget.value)} /></label>
          <button className="pill" type="submit">حفظ السياسة</button>
        </fieldset>
      </form>
      <ul>{data.rules.map(rule => <li key={rule.id}>
        {modes[rule.mode]} · {rule.starts_at.slice(0,5)}–{rule.ends_at.slice(0,5)}
        {' · '}{data.regions.find(r => r.id === rule.governorate_id)?.name_ar ?? 'كل المحافظات'}
        {' · '}{data.areas.find(r => r.id === rule.area_id)?.name_ar ?? 'كل المناطق'}
        {' · '}{data.services.find(s => s.id === rule.service_id)?.title_ar ?? 'كل الخدمات'}
      </li>)}</ul>
    </>}
  </section>;
}
