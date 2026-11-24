import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';

const path = '/v1/admin/safety/directory';
const categories = {
  POLICE: 'الشرطة',
  AMBULANCE: 'الإسعاف',
  CIVIL_DEFENCE: 'الدفاع المدني',
  SAFETY_TEAM: 'فريق السلامة',
  APPROVED_SUPPORT: 'جهة مساعدة معتمدة',
};
type Category = keyof typeof categories;
type Entry = {
  id: string;
  name: string;
  category: Category;
  governorate?: string | null;
  area?: string | null;
  dial_number: string;
  hours?: string | null;
  official_source: string;
  active: boolean;
  valid_until?: string | null;
};
type Form = {
  name: string; category: Category; governorate: string; area: string; dialNumber: string;
  hours: string; officialSource: string; publishVerified: boolean;
};

const blank: Form = {
  name: '', category: 'AMBULANCE', governorate: '', area: '', dialNumber: '',
  hours: '', officialSource: '', publishVerified: false,
};

export function SafetyDirectory() {
  const [entries, setEntries] = useState<Entry[]>([]);
  const [form, setForm] = useState<Form>(blank);
  const [editing, setEditing] = useState<string>();
  const [loaded, setLoaded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');

  async function load() {
    setError('');
    try {
      setEntries(await getJson(path));
      setLoaded(true);
    } catch (error) {
      setError(msgOf(error));
      setLoaded(false);
    }
  }

  useEffect(() => { void load(); }, []);

  function edit(entry: Entry) {
    setEditing(entry.id);
    setForm({
      name: entry.name, category: entry.category, governorate: entry.governorate ?? '',
      area: entry.area ?? '', dialNumber: entry.dial_number, hours: entry.hours ?? '',
      officialSource: entry.official_source, publishVerified: false,
    });
  }

  function clear() {
    setEditing(undefined);
    setForm(blank);
  }

  async function save(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    try {
      await sendJson(editing ? 'PUT' : 'POST', editing ? `${path}/${editing}` : path, {
        ...form,
        governorate: form.governorate.trim() || undefined,
        area: form.area.trim() || undefined,
        hours: form.hours.trim() || undefined,
      });
      clear();
      await load();
    } catch (error) {
      setError(msgOf(error));
    } finally {
      setBusy(false);
    }
  }

  async function deactivate(entry: Entry) {
    if (!window.confirm(`إيقاف نشر ${entry.name}؟`)) return;
    setBusy(true);
    try {
      await sendJson('DELETE', `${path}/${entry.id}`);
      await load();
    } catch (error) {
      setError(msgOf(error));
    } finally {
      setBusy(false);
    }
  }

  return <section aria-label="دليل الطوارئ">
    {error && <p role="alert">{error}</p>}
    {!loaded ? <button className="pill" onClick={() => void load()}>تحديث الدليل</button> : <>
      <form className="card" onSubmit={save}>
        <h2>{editing ? 'تعديل الجهة' : 'إضافة جهة'}</h2>
        <fieldset disabled={busy}>
          <label>الاسم <input required maxLength={100} value={form.name} onChange={e => setForm({...form,name:e.currentTarget.value})}/></label>
          <label>نوع الجهة <select value={form.category} onChange={e => setForm({...form,category:e.currentTarget.value as Category})}>
            {Object.entries(categories).map(([key,label]) => <option key={key} value={key}>{label}</option>)}
          </select></label>
          <label>المحافظة <input maxLength={80} value={form.governorate} onChange={e => setForm({...form,governorate:e.currentTarget.value})}/></label>
          <label>المنطقة <input maxLength={80} value={form.area} onChange={e => setForm({...form,area:e.currentTarget.value})}/></label>
          <label>رقم الاتصال <input dir="ltr" required pattern="[+]?[0-9]{2,15}" value={form.dialNumber} onChange={e => setForm({...form,dialNumber:e.currentTarget.value})}/></label>
          <label>ساعات العمل <input maxLength={120} value={form.hours} onChange={e => setForm({...form,hours:e.currentTarget.value})}/></label>
          <label>مرجع المصدر الرسمي <input required maxLength={500} value={form.officialSource} onChange={e => setForm({...form,officialSource:e.currentTarget.value})}/></label>
          <label><input type="checkbox" checked={form.publishVerified} onChange={e => setForm({...form,publishVerified:e.currentTarget.checked})}/> تحققت من الرقم لدى الجهة الرسمية وأوافق على نشره لمدة 90 يومًا</label>
          <button className="pill" type="submit">{form.publishVerified ? 'نشر الرقم المعتمد' : 'حفظ كمسودة'}</button>
          {editing && <button className="pill" type="button" onClick={clear}>إلغاء التعديل</button>}
        </fieldset>
      </form>
      <ul>
        {entries.map(entry => <li className="card" key={entry.id}>
          <strong>{entry.name}</strong> · {categories[entry.category]} · <bdi>{entry.dial_number}</bdi>
          <p>{[entry.governorate, entry.area].filter(Boolean).join('، ')} {entry.official_source}</p>
          <p>{entry.active && entry.valid_until && Date.parse(entry.valid_until) > Date.now() ? 'منشور' : 'غير منشور'}</p>
          <button className="pill" disabled={busy} onClick={() => edit(entry)}>تعديل</button>
          {entry.active && <button className="pill" disabled={busy} onClick={() => void deactivate(entry)}>إيقاف النشر</button>}
        </li>)}
      </ul>
    </>}
  </section>;
}
