import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {Chip, Notice, Panel, Table} from './ui';
import {PhoneCall, PlusCircle, RefreshCw, ShieldAlert, CheckCircle, Clock} from 'lucide-react';

const path = '/v1/admin/safety/directory';
const categories = {
  POLICE: 'الشرطة والأمن الداخلي',
  AMBULANCE: 'منظومة الإسعاف الفوري',
  CIVIL_DEFENCE: 'الدفاع المدني والإطفاء',
  SAFETY_TEAM: 'فريق السلامة الميداني',
  APPROVED_SUPPORT: 'جهة مساعدة طبية معتمدة',
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
  name: string;
  category: Category;
  governorate: string;
  area: string;
  dialNumber: string;
  hours: string;
  officialSource: string;
  publishVerified: boolean;
};

const blank: Form = {
  name: '',
  category: 'AMBULANCE',
  governorate: '',
  area: '',
  dialNumber: '',
  hours: '24/7 على مدار الساعة',
  officialSource: '',
  publishVerified: true,
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
    } catch (err) {
      setError(msgOf(err));
      setLoaded(false);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  function edit(entry: Entry) {
    setEditing(entry.id);
    setForm({
      name: entry.name,
      category: entry.category,
      governorate: entry.governorate ?? '',
      area: entry.area ?? '',
      dialNumber: entry.dial_number,
      hours: entry.hours ?? '',
      officialSource: entry.official_source,
      publishVerified: Boolean(entry.active),
    });
    window.scrollTo({top: 0, behavior: 'smooth'});
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
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  async function deactivate(entry: Entry) {
    if (!window.confirm(`هل أنت متأكد من إيقاف نشر رقم طوارئ "${entry.name}"؟`)) return;
    setBusy(true);
    try {
      await sendJson('DELETE', `${path}/${entry.id}`);
      await load();
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="safety-directory-page">
      {error && (
        <div style={{marginBottom: 16}}>
          <Notice tone="danger">{error}</Notice>
        </div>
      )}

      <Panel
        title={editing ? 'تعديل بيانات جهة الطوارئ' : 'إضافة جهة طوارئ جديدة'}
        subtitle="توثيق واعتماد أرقام الطوارئ الرسمية لتظهر لكوادر التمريض والمرضى وفرق الاستجابة السريعة"
        action={
          <button className="action-btn" onClick={() => void load()} title="تحديث القائمة">
            <RefreshCw size={15} />
            <span>تحديث</span>
          </button>
        }
      >
        <form onSubmit={save} className="form">
          <label>
            اسم الجهة أو المنظومة
            <input
              required
              maxLength={100}
              placeholder="مثال: الإسعاف السريع - الهلال الأحمر"
              value={form.name}
              onChange={e => setForm({...form, name: e.currentTarget.value})}
            />
          </label>

          <label>
            نوع جهة الطوارئ
            <select
              value={form.category}
              onChange={e => setForm({...form, category: e.currentTarget.value as Category})}
            >
              {Object.entries(categories).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
          </label>

          <label>
            المحافظة (اختياري للتغطية العامة)
            <input
              maxLength={80}
              placeholder="مثال: دمشق"
              value={form.governorate}
              onChange={e => setForm({...form, governorate: e.currentTarget.value})}
            />
          </label>

          <label>
            المنطقة (اختياري)
            <input
              maxLength={80}
              placeholder="مثال: المزة"
              value={form.area}
              onChange={e => setForm({...form, area: e.currentTarget.value})}
            />
          </label>

          <label>
            رقم الاتصال المباشر
            <input
              dir="ltr"
              required
              pattern="[+]?[0-9]{2,15}"
              placeholder="110 أو +963..."
              value={form.dialNumber}
              onChange={e => setForm({...form, dialNumber: e.currentTarget.value})}
            />
          </label>

          <label>
            ساعات العمل والاستجابة
            <input
              maxLength={120}
              placeholder="مثال: 24/7 على مدار الساعة"
              value={form.hours}
              onChange={e => setForm({...form, hours: e.currentTarget.value})}
            />
          </label>

          <label style={{gridColumn: '1 / -1'}}>
            مرجع ومستند التوثيق الرسمي
            <input
              required
              maxLength={500}
              placeholder="مثال: قرار وزارة الصحة رقم 14 / الموقع الرسمي للدفاع المدني"
              value={form.officialSource}
              onChange={e => setForm({...form, officialSource: e.currentTarget.value})}
            />
          </label>

          <div style={{gridColumn: '1 / -1', margin: '4px 0'}}>
            <label className="check">
              <input
                type="checkbox"
                checked={form.publishVerified}
                onChange={e => setForm({...form, publishVerified: e.currentTarget.checked})}
              />
              <span>تحققت من صحة وموثوقية الرقم لدى الجهة الرسمية وأوافق على اعتماده ونشره لمدة 90 يوماً</span>
            </label>
          </div>

          <div className="actions" style={{gridColumn: '1 / -1', marginTop: 8}}>
            <button className="pill on" type="submit" disabled={busy}>
              {editing ? 'حفظ التعديلات' : form.publishVerified ? 'نشر الرقم المعتمد' : 'حفظ كمسودة غير معتمدة'}
            </button>
            {editing && (
              <button className="pill" type="button" onClick={clear}>
                إلغاء التعديل
              </button>
            )}
          </div>
        </form>
      </Panel>

      <div style={{marginTop: 24}}>
        <Panel
          title="سجل جهات الطوارئ المعتمدة في النظام"
          subtitle={`إجمالي الجهات المسجلة: ${entries.length} جهة اتصال`}
        >
          {entries.length === 0 ? (
            <div className="empty-hint">لا توجد جهات طوارئ مسجلة حالياً. استخدم النموذج أعلاه لإضافة أول جهة.</div>
          ) : (
            <Table
              head={['الجهة والاسم', 'التصنيف', 'رقم الاتصال', 'النطاق الجغرافي', 'ساعات العمل', 'حالة النشر', 'الإجراءات']}
              rows={entries.map(entry => {
                const isCurrent = entry.active && entry.valid_until && Date.parse(entry.valid_until) > Date.now();
                return [
                  <div key="name" style={{display: 'flex', flexDirection: 'column'}}>
                    <strong style={{color: 'var(--navy)', fontSize: 14}}>{entry.name}</strong>
                    <small style={{color: 'var(--sub)', fontSize: 11}}>{entry.official_source}</small>
                  </div>,
                  <Chip key="cat" tone={entry.category === 'AMBULANCE' || entry.category === 'SAFETY_TEAM' ? 'danger' : 'info'}>
                    {categories[entry.category] ?? entry.category}
                  </Chip>,
                  <span key="dial" dir="ltr" style={{fontFamily: 'monospace', fontWeight: 700, fontSize: 14, color: 'var(--navy)'}}>
                    {entry.dial_number}
                  </span>,
                  [entry.governorate, entry.area].filter(Boolean).join(' - ') || 'كافة المناطق (تغطية عامة)',
                  entry.hours || '24 ساعة',
                  <Chip key="status" tone={isCurrent ? 'success' : 'warn'}>
                    {isCurrent ? 'معتمد ومنشور' : 'مسودة / موقوف'}
                  </Chip>,
                  <div key="act" className="acts">
                    <button className="pill" disabled={busy} onClick={() => edit(entry)}>
                      تعديل
                    </button>
                    {entry.active && (
                      <button className="pill danger" disabled={busy} onClick={() => void deactivate(entry)}>
                        إيقاف النشر
                      </button>
                    )}
                  </div>,
                ];
              })}
            />
          )}
        </Panel>
      </div>
    </div>
  );
}
