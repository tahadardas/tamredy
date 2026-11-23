import {useCallback, useEffect, useState} from 'react';
import {getJson, sendJson} from './session';
import type {Live} from './pages';
import {Notice, Panel, Table} from './ui';
import {useBusy} from './widgets';

function Regions() {
  const [data, setData] = useState<any[]>([]); const [gname, setGname] = useState(''); const [aname, setAname] = useState<Record<string, string>>({}); const [acoord, setAcoord] = useState<Record<string, {lat?: string; lng?: string}>>({}); const {err, run} = useBusy();
  const load = useCallback(async () => setData((await getJson('/v1/admin/regions')).governorates), []);
  useEffect(() => { void load().catch(() => undefined); }, [load]);
  const go = (f: () => Promise<unknown>) => run(async () => { await f(); await load(); });
  return <Panel title="المحافظات والمناطق">
    <p className="hint">تظهر للممرض عند التسجيل وفي ملفه. للتوسع أضف محافظة ثم مناطقها. لا يُحذف شيء؛ التعطيل يخفيه عن التسجيل ويُبقي سجلات الممرضين.</p>
    {data.map(g => <div key={g.id} className="region">
      <div className="acts"><b>{g.name_ar}</b><small>({g.nurses} ممرض)</small>
        <button className="pill" onClick={() => void go(() => sendJson('PATCH', `/v1/admin/regions/governorates/${g.id}`, {active: !g.active}))}>{g.active ? 'تعطيل' : 'تفعيل'}</button></div>
      <div className="skills">{g.areas.map((a: any) => <span key={a.id} className="acts"><span style={{opacity: a.active ? 1 : .45}}>{a.name_ar}{a.nurses ? ` (${a.nurses})` : ''}{a.lat == null ? ' ⚠ بلا إحداثيات' : ''}</span>
        <button className="pill" onClick={() => void go(() => sendJson('PATCH', `/v1/admin/regions/areas/${a.id}`, {active: !a.active}))}>{a.active ? 'تعطيل' : 'تفعيل'}</button></span>)}</div>
      <div className="toolbar"><input placeholder="منطقة جديدة" value={aname[g.id] ?? ''} onChange={e => setAname({...aname, [g.id]: e.target.value})}/>
        <input dir="ltr" placeholder="خط العرض (اختياري)" value={acoord[g.id]?.lat ?? ''} onChange={e => setAcoord({...acoord, [g.id]: {...acoord[g.id], lat: e.target.value}})}/>
        <input dir="ltr" placeholder="خط الطول (اختياري)" value={acoord[g.id]?.lng ?? ''} onChange={e => setAcoord({...acoord, [g.id]: {...acoord[g.id], lng: e.target.value}})}/>
        <button className="pill on" onClick={() => { const n = (aname[g.id] ?? '').trim(); if (n) void go(async () => { const c = acoord[g.id] ?? {}; await sendJson('POST', '/v1/admin/regions/areas', {nameAr: n, governorateId: g.id, ...(c.lat && c.lng ? {lat: Number(c.lat), lng: Number(c.lng)} : {})}); setAname({...aname, [g.id]: ''}); }); }}>+ إضافة منطقة</button></div>
    </div>)}
    <div className="toolbar"><input placeholder="محافظة جديدة" value={gname} onChange={e => setGname(e.target.value)}/>
      <button className="pill on" onClick={() => { const n = gname.trim(); if (n) void go(async () => { await sendJson('POST', '/v1/admin/regions/governorates', {nameAr: n}); setGname(''); }); }}>+ إضافة محافظة</button></div>
    {err && <p className="hint err">{err}</p>}
  </Panel>;
}

const ACTIONS: Record<string, string> = {
  'nurse.created': 'إضافة ممرض', 'nurse.updated': 'تعديل ممرض', 'nurse.deleted': 'حذف ممرض', 'nurse.suspended': 'إيقاف ممرض', 'nurse.active': 'تفعيل ممرض', 'nurse.skills_set': 'تعديل المهارات',
  'nurse.document_uploaded': 'رفع مستند', 'nurse.document_viewed': 'الاطلاع على مستند', 'nurse.document_deleted': 'حذف مستند', 'settings.changed': 'تغيير إعدادات',
  'staff.updated': 'تعديل حساب إداري', 'staff.deleted': 'حذف حساب إداري', 'user.created': 'إنشاء حساب', 'user.password_reset': 'إعادة كلمة مرور',
  'credential.approved': 'اعتماد رخصة', 'credential.rejected': 'رفض رخصة', 'credential.needs_info': 'طلب معلومات للرخصة',
};
const when = (v: string) => new Date(v).toLocaleString('ar-SY');

export function AuditLog({live}: {live: Live}) {
  const [items, setItems] = useState<any[] | null>(null); const [f, setF] = useState(''); const [err, setErr] = useState('');
  const load = useCallback(async () => { try { setItems((await getJson(`/v1/admin/audit?limit=200${f ? `&action=${f}` : ''}`)).items); setErr(''); } catch (e) { setErr((e as Error).message); } }, [f]);
  useEffect(() => { void load(); }, [load, live.token]);
  return <Panel title="سجل التدقيق">
    <div className="toolbar"><select value={f} onChange={e => setF(e.target.value)}><option value="">كل العمليات</option><option value="nurse.">الممرضون</option><option value="nurse.document">المستندات</option><option value="settings.">الإعدادات</option><option value="credential.">الرخص</option><option value="user.">الحسابات</option><option value="staff.">الإداريون</option></select></div>
    {err && <p className="hint err">{err}</p>}
    {items && <Table head={['الوقت', 'المنفّذ', 'العملية', 'تفاصيل']} rows={items.map(a => [when(a.occurred_at), a.actor, ACTIONS[a.action] ?? a.action,
      <small key="d" dir="ltr">{Object.keys(a.detail ?? {}).length ? JSON.stringify(a.detail).slice(0, 120) : ''}</small>])}/>}
    {items && !items.length && <p className="hint">لا سجلات.</p>}
  </Panel>;
}

function Section({k, title, desc, value, reload, children}: {k: string; title: string; desc: string; value: any; reload: () => Promise<void>;
  children: (v: any, set: (p: any) => void) => React.ReactNode}) {
  const [v, setV] = useState<any>(value); const {busy, err, run} = useBusy(); const [ok, setOk] = useState('');
  useEffect(() => setV(value), [value]);
  return <Panel title={title}>
    <p className="hint">{desc}</p>{children(v, p => { setOk(''); setV({...v, ...p}); })}
    {err && <p className="hint err">{err}</p>}{ok && <p className="hint">{ok}</p>}
    <div className="actions"><button className="pill on" disabled={busy} onClick={() => void run(async () => { await sendJson('PUT', `/v1/admin/system-settings/${k}`, v); await reload(); setOk('تم الحفظ'); })}>حفظ</button></div>
  </Panel>;
}

export function SettingsPage({live}: {live: Live}) {
  const [s, setS] = useState<any>(null); const [err, setErr] = useState('');
  const load = useCallback(async () => { try { setS((await getJson('/v1/admin/system-settings')).settings); setErr(''); } catch (e) { setErr((e as Error).message); } }, []);
  useEffect(() => { void load(); }, [load]);
  if (!s) return <Panel title="الإعدادات"><p className="hint">{err || 'جارٍ التحميل...'}</p></Panel>;
  return <>
    <Section k="orders" title="استقبال الطلبات" desc="إيقاف مؤقت لإنشاء طلبات جديدة (صيانة أو طوارئ). الطلبات الجارية لا تتأثر." value={s.orders} reload={load}>
      {(v, set) => <div className="form">
        <label className="check"><input type="checkbox" checked={v.accepting} onChange={e => set({accepting: e.target.checked})}/> يستقبل التطبيق طلبات جديدة</label>
        <label style={{gridColumn: 'span 2'}}>الرسالة عند الإيقاف<input value={v.pausedMessage} onChange={e => set({pausedMessage: e.target.value})}/></label></div>}
    </Section>
    <Regions/>
    <Section k="registration" title="التسجيل الذاتي" desc="السماح بإنشاء حسابات جديدة من التطبيقين. الممرض الجديد لا يستقبل طلبات قبل اعتماد رخصته." value={s.registration ?? {patients: true, nurses: true}} reload={load}>
      {(v, set) => <div className="form">
        <label className="check"><input type="checkbox" checked={v.patients} onChange={e => set({patients: e.target.checked})}/> تسجيل المرضى مفتوح</label>
        <label className="check"><input type="checkbox" checked={v.nurses} onChange={e => set({nurses: e.target.checked})}/> تسجيل الممرضين مفتوح</label></div>}
    </Section>
    <Section k="dispatch" title="سياسة توزيع الطلبات" desc="يوزع البحث المفتوح الطلب على جميع المؤهلين ضمن نطاق واحد حتى انتهاء المهلة." value={s.dispatch} reload={load}>
      {(v, set) => <>
        <label className="check">
          <input type="checkbox" checked={v.openEnabled === true} onChange={e => set({...v, openEnabled: e.target.checked})}/>
          تشغيل البحث المفتوح للطلبات الجديدة
        </label>
        <div className="form">
          {([
            ['offerDurationSeconds', 'مهلة البحث (ثانية)', 60],
            ['radiusMeters', 'نطاق البحث (متر)', 10000],
            ['maxHeartbeatAgeSeconds', 'أقصى عمر للنبض (ثانية)', 60],
            ['maxLocationAgeSeconds', 'أقصى عمر للموقع (ثانية)', 120],
            ['maxLocationAccuracyMeters', 'أقصى خطأ للموقع (متر)', 100],
          ] as const).map(([key, label, fallback]) => <label key={key}>{label}
            <input type="number" value={v[key] ?? fallback} onChange={e => set({...v, [key]: Number(e.target.value)})}/>
          </label>)}
        </div>
        {v.waves.map((w: any, i: number) => <div className="form" key={i}>
        {(['radiusM', 'seconds'] as const).map(key => <label key={key}>{{radiusM: `نصف القطر (م) — موجة ${i + 1}`, seconds: 'المهلة (ثانية)'}[key]}
          <input type="number" value={w[key]} onChange={e => set({...v, waves: v.waves.map((x: any, j: number) => j === i ? {...x, [key]: Number(e.target.value)} : x)})}/></label>)}</div>)}
        <div className="actions">{v.waves.length < 5 && <button className="pill" onClick={() => set({...v, waves: [...v.waves, {radiusM: v.waves.at(-1).radiusM + 5000, seconds: 20}]})}>+ موجة</button>}
          {v.waves.length > 1 && <button className="pill" onClick={() => set({...v, waves: v.waves.slice(0, -1)})}>− حذف الأخيرة</button>}</div>
        <Notice>تُقرأ الإعدادات عند بدء كل موجة.</Notice></>}
    </Section>
    <Section k="security" title="الأمان" desc="تسجيل الخروج التلقائي عند الخمول، والحد الأدنى لطول كلمة المرور." value={s.security} reload={load}>
      {(v, set) => <div className="form"><label>الخروج التلقائي بعد (دقيقة)<input type="number" value={v.idleMinutes} onChange={e => set({idleMinutes: Number(e.target.value)})}/></label>
        <label>أدنى طول لكلمة المرور<input type="number" value={v.passwordMinLength} onChange={e => set({passwordMinLength: Number(e.target.value)})}/></label>
        <label>كلمة المرور الافتراضية للحسابات الجديدة (يغيّرها المستخدم عند أول دخول)<input dir="ltr" value={v.defaultPassword ?? '123456'} onChange={e => set({defaultPassword: e.target.value})}/></label></div>}
    </Section>
    <Section k="company" title="بيانات الشركة" desc="تظهر في الفواتير والتقارير." value={s.company} reload={load}>
      {(v, set) => <div className="form">{([['name', 'اسم الشركة'], ['phone', 'الهاتف'], ['email', 'البريد'], ['address', 'العنوان'], ['currencyLabel', 'رمز العملة']] as const).map(([k, l]) =>
        <label key={k}>{l}<input value={v[k] ?? ''} onChange={e => set({[k]: e.target.value})}/></label>)}</div>}
    </Section>
  </>;
}
