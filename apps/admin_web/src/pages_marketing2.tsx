import {msgOf} from './session';
import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {Notice, Panel, Table} from './ui';
import {Field, n, send} from './pages_marketing';

type Feature = {key: string; enabled: boolean; config: any};

/** One-click templates for code-based campaigns: welcome (new users), seasonal, corporate. Codes are switched on/off in the list. */
export function QuickPromos({live}: {live: NonNullable<Live>}) {
  const [kind, setKind] = useState('welcome');
  const [f, setF] = useState<any>({code: '', percent: '20', maxDiscount: '1000', validTo: '', maxRedemptions: ''});
  const [items, setItems] = useState<any[]>([]);
  const [msg, setMsg] = useState('');
  const load = async () => { try { setItems((await live.get('/v1/admin/promos')).items); } catch { /* shown empty */ } };
  useEffect(() => { void load(); }, [live.token]);
  const presets: Record<string, string> = {welcome: 'كود ترحيب للمستخدمين الجدد (للطلب الأول فقط، مرة لكل مريض)', season: 'كود موسمي (مثل رمضان) بتاريخ انتهاء', corporate: 'كود شركة/مؤسسة بعدد استخدامات محدد'};
  async function create() {
    setMsg('');
    try {
      const b: any = {code: f.code.trim(), type: 'PERCENT', value: Number(f.percent), description: presets[kind]};
      if (f.maxDiscount) b.maxDiscount = Number(f.maxDiscount);
      if (kind === 'welcome') { b.firstOrderOnly = true; b.perUserLimit = 1; }
      if (kind === 'season') { if (!f.validTo) throw Error('حدد تاريخ الانتهاء'); b.validTo = new Date(f.validTo + 'T23:59:59').toISOString(); b.perUserLimit = 3; }
      if (kind === 'corporate') { if (!f.maxRedemptions) throw Error('حدد عدد الاستخدامات'); b.maxRedemptions = Number(f.maxRedemptions); b.perUserLimit = 5; }
      await send(live, 'POST', '/v1/admin/promos', b);
      setMsg('تم إنشاء الكود.'); setF({...f, code: ''}); await load();
    } catch (e) { setMsg(`تعذر الإنشاء: ${msgOf(e)}`); }
  }
  return <Panel title="أكواد الحملات (ترحيب • موسمي • شركات)">
    <div className="filters" style={{marginBottom: 14}}>{[['welcome', 'ترحيب'], ['season', 'موسمي'], ['corporate', 'شركات']].map(([k, l]) => <button key={k} className={'pill ' + (kind === k ? 'on' : '')} onClick={() => setKind(k!)}>{l}</button>)}</div>
    <p className="hint">{presets[kind]}</p>
    <div className="form">
      <Field label="الكود"><input dir="ltr" value={f.code} onChange={e => setF({...f, code: e.target.value})} placeholder="WELCOME20"/></Field>
      <Field label="نسبة الخصم %"><input type="number" value={f.percent} onChange={e => setF({...f, percent: e.target.value})}/></Field>
      <Field label="أقصى خصم (ل.س)"><input type="number" value={f.maxDiscount} onChange={e => setF({...f, maxDiscount: e.target.value})}/></Field>
      {kind === 'season' && <Field label="ينتهي في"><input type="date" value={f.validTo} onChange={e => setF({...f, validTo: e.target.value})}/></Field>}
      {kind === 'corporate' && <Field label="عدد الاستخدامات الكلي"><input type="number" value={f.maxRedemptions} onChange={e => setF({...f, maxRedemptions: e.target.value})}/></Field>}
    </div>
    <div className="actions"><button className="pill on" onClick={() => void create()}>إنشاء الكود</button></div>
    {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}
    <Table head={['الكود', 'الخصم', 'الاستخدام', 'الحالة']} rows={items.filter(p => p.source === 'ADMIN').slice(0, 15).map(p => [<b dir="ltr">{p.code}</b>, `${Number(p.value)}${p.type === 'PERCENT' ? '%' : ' ل.س'}`, `${p.used}${p.max_redemptions ? ` / ${p.max_redemptions}` : ''}`,
      <button className={'pill ' + (p.active ? 'on' : '')} onClick={async () => { await send(live, 'PATCH', `/v1/admin/promos/${p.id}`, {active: !p.active}); await load(); }}>{p.active ? 'مفعّل' : 'موقوف'}</button>])}/>
  </Panel>;
}

/** Visit packs: templates (config) + grant to a patient by phone after they pay the company. */
function PacksConfig({live, feature, reload, Card}: {live: NonNullable<Live>; feature: Feature; reload: () => Promise<void>; Card: any}) {
  const [grants, setGrants] = useState<any[]>([]);
  const [g, setG] = useState({phone: '', idx: '0'});
  const [msg, setMsg] = useState('');
  const load = async () => { try { setGrants((await live.get('/v1/admin/marketing/packs')).items); } catch { /* empty */ } };
  useEffect(() => { void load(); }, [live.token]);
  const templates: any[] = feature.config.templates ?? [];
  async function grant() {
    setMsg('');
    const t = templates[Number(g.idx)];
    try { await send(live, 'POST', '/v1/admin/marketing/packs/grant', {phone: g.phone.trim(), name: t.name, visits: t.visits, percent: t.percent, validDays: t.validDays}); setMsg('تم منح الباقة وأُبلغ المريض.'); setG({...g, phone: ''}); await load(); }
    catch (e) { setMsg(`تعذر المنح: ${msgOf(e)}`); }
  }
  return <Card live={live} f={feature} reload={reload} title="باقات الزيارات" desc="باقة عدد من الزيارات بخصم ثابت. يدفع المريض للشركة خارج التطبيق، ثم تمنحه الباقة من هنا فيُطبَّق خصمها تلقائيًا على زياراته حتى تنتهي أو تنقضي مدتها.">
    {(cfg: any, set: any) => <>
      <Table head={['القالب', 'الزيارات', 'الخصم %', 'صلاحية (يوم)', '']} rows={(cfg.templates ?? []).map((t: any, i: number) => [t.name, t.visits, t.percent, t.validDays,
        <button className="pill" onClick={() => set('templates', cfg.templates.filter((_: any, j: number) => j !== i))}>حذف</button>])}/>
      <div className="actions"><button className="pill" onClick={() => set('templates', [...(cfg.templates ?? []), {name: 'باقة جديدة', visits: 4, percent: 10, validDays: 60}])}>إضافة قالب</button></div>
      {(cfg.templates ?? []).map((t: any, i: number) => <div className="form" key={i}>
        <Field label="الاسم"><input value={t.name} onChange={e => set('templates', cfg.templates.map((x: any, j: number) => j === i ? {...x, name: e.target.value} : x))}/></Field>
        <Field label="الزيارات"><input type="number" value={t.visits} onChange={e => set('templates', cfg.templates.map((x: any, j: number) => j === i ? {...x, visits: Number(e.target.value)} : x))}/></Field>
        <Field label="الخصم %"><input type="number" value={t.percent} onChange={e => set('templates', cfg.templates.map((x: any, j: number) => j === i ? {...x, percent: Number(e.target.value)} : x))}/></Field>
        <Field label="صلاحية (يوم)"><input type="number" value={t.validDays} onChange={e => set('templates', cfg.templates.map((x: any, j: number) => j === i ? {...x, validDays: Number(e.target.value)} : x))}/></Field>
      </div>)}
    </>}
  </Card>;
}

export function Packs(props: {live: NonNullable<Live>; feature: Feature; reload: () => Promise<void>; Card: any}) {
  const {live, feature} = props;
  const [grants, setGrants] = useState<any[]>([]);
  const [g, setG] = useState({phone: '', idx: '0'});
  const [msg, setMsg] = useState('');
  const load = async () => { try { setGrants((await live.get('/v1/admin/marketing/packs')).items); } catch { /* empty */ } };
  useEffect(() => { void load(); }, [live.token]);
  const templates: any[] = feature.config.templates ?? [];
  async function grant() {
    setMsg('');
    const t = templates[Number(g.idx)];
    if (!t) { setMsg('تعذر المنح: لا قالب'); return; }
    try { await send(live, 'POST', '/v1/admin/marketing/packs/grant', {phone: g.phone.trim(), name: t.name, visits: t.visits, percent: t.percent, validDays: t.validDays}); setMsg('تم منح الباقة وأُبلغ المريض.'); setG({...g, phone: ''}); await load(); }
    catch (e) { setMsg(`تعذر المنح: ${msgOf(e)}`); }
  }
  return <>
    <PacksConfig {...props}/>
    <Panel title="منح باقة لمريض">
      <div className="form">
        <Field label="هاتف المريض"><input dir="ltr" value={g.phone} onChange={e => setG({...g, phone: e.target.value})} placeholder="+963911111111"/></Field>
        <Field label="القالب"><select value={g.idx} onChange={e => setG({...g, idx: e.target.value})}>{templates.map((t, i) => <option key={i} value={i}>{t.name} — {t.visits} زيارات / {t.percent}%</option>)}</select></Field>
      </div>
      <div className="actions"><button className="pill on" onClick={() => void grant()}>منح الباقة</button></div>
      {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}
      <Table head={['المريض', 'الباقة', 'المستخدم', 'الخصم', 'تنتهي']} rows={grants.map(x => [x.patient, x.name, `${x.used} / ${x.visits}`, `${Number(x.percent)}%`, String(x.expires_at).slice(0, 10)])}/>
    </Panel>
  </>;
}

/** Broadcast notifications to all patients (opted-in only) or all / available nurses, with an optional code. */
export function Broadcasts({live, feature, reload, Card}: {live: NonNullable<Live>; feature: Feature; reload: () => Promise<void>; Card: any}) {
  const [f, setF] = useState({audience: 'ALL_PATIENTS', title: '', body: '', promoCode: ''});
  const [reach, setReach] = useState<any>(null);
  const [hist, setHist] = useState<any[]>([]);
  const [msg, setMsg] = useState('');
  const loadHist = async () => { try { setHist((await live.get('/v1/admin/broadcasts')).items); } catch { /* empty */ } };
  const loadReach = async () => { try { setReach(await live.get(`/v1/admin/broadcasts/preview?audience=${f.audience}`)); } catch { setReach(null); } };
  useEffect(() => { void loadHist(); }, [live.token]);
  useEffect(() => { void loadReach(); }, [f.audience, live.token]);
  const names: Record<string, string> = {ALL_PATIENTS: 'كل المرضى (الموافقين)', ALL_NURSES: 'كل الممرضين', AVAILABLE_NURSES: 'الممرضون المتاحون الآن'};
  async function sendNow() {
    setMsg('');
    if (!window.confirm(`إرسال إلى ${names[f.audience]} (${reach?.devices ?? 0} جهاز)؟`)) return;
    try { const r = await send(live, 'POST', '/v1/admin/broadcasts', {audience: f.audience, title: f.title, body: f.body, ...(f.promoCode ? {promoCode: f.promoCode} : {})}); setMsg(`وُضعت في قائمة الإرسال لـ ${r.queuedFor} جهاز.`); setF({...f, title: '', body: ''}); await loadHist(); }
    catch (e) { setMsg(`تعذر الإرسال: ${msgOf(e)}`); }
  }
  return <Card live={live} f={feature} reload={reload} title="الإشعارات والرسائل التسويقية" desc="أرسل إشعارًا لكل المرضى أو كل الممرضين أو المتاحين الآن. المرضى يصلهم فقط من وافق على الرسائل التسويقية من تطبيقه. يتولى العامل الإرسال خلال ثوانٍ.">
    <div className="form">
      <Field label="الجمهور"><select value={f.audience} onChange={e => setF({...f, audience: e.target.value})}>{Object.entries(names).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></Field>
      <Field label="العنوان"><input maxLength={80} value={f.title} onChange={e => setF({...f, title: e.target.value})}/></Field>
      <Field label="كود خصم يُذكر في الرسالة (اختياري)"><input dir="ltr" value={f.promoCode} onChange={e => setF({...f, promoCode: e.target.value})}/></Field>
    </div>
    <label className="form" style={{display: 'block'}}><span className="hint">نص الرسالة (حتى 300 حرف)</span><textarea style={{width: '100%', minHeight: 80, padding: 10, border: '1px solid var(--border)', borderRadius: 10, font: 'inherit'}} maxLength={300} value={f.body} onChange={e => setF({...f, body: e.target.value})}/></label>
    <p className="hint">سيصل إلى: <b>{reach ? `${reach.users} مستخدم • ${reach.devices} جهاز` : '—'}</b></p>
    <div className="actions"><button className="pill on" disabled={!feature.enabled || f.title.length < 2 || f.body.length < 2} onClick={() => void sendNow()}>إرسال</button></div>
    {!feature.enabled && <p className="hint err">فعّل الميزة بالمفتاح أعلاه أولًا.</p>}
    {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}
    <Table head={['التاريخ', 'الجمهور', 'العنوان', 'الحالة', 'وصل / فشل']} rows={hist.map(h => [String(h.created_at).slice(0, 16).replace('T', ' '), names[h.audience] ?? h.audience, h.title,
      h.status === 'DONE' ? 'تم' : h.status === 'FAILED' ? 'فشل (FCM غير مُهيّأ)' : h.status === 'SENDING' ? 'جارٍ الإرسال' : 'في الانتظار', `${h.sent} / ${h.failed}`])}/>
    <button className="pill" onClick={() => void loadHist()}>تحديث السجل</button>
  </Card>;
}
