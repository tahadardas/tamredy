import {msgOf} from './session';
import {sendJson} from './session';
import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {Chip, Notice, Panel, Table} from './ui';
import {PromoAbuse} from './pages_fees';

const n = (v: number | string) => Number(v).toLocaleString('en-US');
type Svc = {id: string; code: string; title_ar: string; description_ar: string | null; price_amount: string; included_minutes: number; block_minutes: number; block_price: string;
  expected_minutes: number; rounding_step: number; commission_bps: number; sort_order: number; active: boolean; dispatch_approved: boolean};

/** Same formula as the server (apps/api/src/pricing/pricing.ts) — preview only; the server is the source of truth. */
const gross = (s: {base: number; inc: number; block: number; blockPrice: number}, minutes: number) =>
  s.base + Math.ceil(Math.max(0, minutes - s.inc) / s.block) * s.blockPrice;

function useApi(live: Live, path: string) {
  const [data, setData] = useState<any>(null);
  const [err, setErr] = useState('');
  const load = async () => { if (!live) return; try { setData(await live.get(path)); setErr(''); } catch (e) { setErr(msgOf(e)); } };
  useEffect(() => { void load(); }, [live?.token]);
  return {data, err, load};
}
const NeedLogin = ({title}: {title: string}) => <Panel title={title}><p className="hint">سجّل الدخول (أيقونة الاتصال أعلى الصفحة) بحساب إدارة لإدارة هذه البيانات.</p></Panel>;
const send = (_live: unknown, method: string, path: string, body?: unknown) => sendJson(method, path, body);
const Field = ({label, children}: {label: string; children: React.ReactNode}) => <label>{label}{children}</label>;

export function ServicesPrices({live}: {live: Live}) {
  const {data, err, load} = useApi(live, '/v1/admin/services');
  const blank = {id: '', code: '', titleAr: '', descriptionAr: '', price: '', includedMinutes: '30', blockMinutes: '15', blockPrice: '0', expectedMinutes: '30', roundingStep: '1', commissionBps: '2000', sortOrder: '0'};
  const [f, setF] = useState<any>(blank);
  const [msg, setMsg] = useState('');
  if (!live) return <NeedLogin title="الخدمات والأسعار"/>;
  const set = (k: string) => (e: any) => setF((p: any) => ({...p, [k]: e.target.value}));
  const num = (v: string) => Number(v || 0);
  const edit = (s: Svc) => setF({id: s.id, code: s.code, titleAr: s.title_ar, descriptionAr: s.description_ar ?? '', price: String(Number(s.price_amount)), includedMinutes: String(s.included_minutes),
    blockMinutes: String(s.block_minutes), blockPrice: String(Number(s.block_price)), expectedMinutes: String(s.expected_minutes), roundingStep: String(s.rounding_step), commissionBps: String(s.commission_bps), sortOrder: String(s.sort_order)});
  async function save() {
    setMsg('');
    try {
      const body: any = {titleAr: f.titleAr, descriptionAr: f.descriptionAr || undefined, price: num(f.price), includedMinutes: num(f.includedMinutes), blockMinutes: num(f.blockMinutes), blockPrice: num(f.blockPrice),
        expectedMinutes: num(f.expectedMinutes), roundingStep: num(f.roundingStep), commissionBps: num(f.commissionBps), sortOrder: num(f.sortOrder)};
      if (f.id) await send(live!, 'PATCH', `/v1/admin/services/${f.id}`, body);
      else await send(live!, 'POST', '/v1/admin/services', {...body, code: f.code});
      setMsg('تم الحفظ — يظهر التغيير في التطبيقات فورًا.'); setF(blank); await load();
    } catch (e) { setMsg(`تعذر الحفظ: ${msgOf(e)}`); }
  }
  async function toggle(s: Svc, field: 'active' | 'dispatchApproved') {
    try { await send(live!, 'PATCH', `/v1/admin/services/${s.id}`, {[field]: field === 'active' ? !s.active : !s.dispatch_approved}); await load(); } catch (e) { setMsg(msgOf(e)); }
  }
  const rule = {base: num(f.price), inc: Math.max(1, num(f.includedMinutes)), block: Math.max(1, num(f.blockMinutes)), blockPrice: num(f.blockPrice)};
  const step = Math.max(1, num(f.roundingStep));
  const rounded = (m: number) => Math.ceil(gross(rule, m) / step) * step;
  const items: Svc[] = data?.items ?? [];
  return <>
    <Panel title={f.id ? `تعديل الخدمة: ${f.titleAr}` : 'إضافة خدمة جديدة'}>
      <div className="form">
        <Field label="الرمز (أحرف إنكليزية كبيرة)"><input dir="ltr" disabled={!!f.id} value={f.code} onChange={set('code')} placeholder="WOUND_CARE"/></Field>
        <Field label="اسم الخدمة"><input value={f.titleAr} onChange={set('titleAr')}/></Field>
        <Field label="وصف مختصر"><input value={f.descriptionAr} onChange={set('descriptionAr')}/></Field>
        <Field label="السعر الأساسي (ل.س)"><input type="number" value={f.price} onChange={set('price')}/></Field>
        <Field label="الدقائق المشمولة بالسعر الأساسي"><input type="number" value={f.includedMinutes} onChange={set('includedMinutes')}/></Field>
        <Field label="طول كل شريحة إضافية (دقيقة)"><input type="number" value={f.blockMinutes} onChange={set('blockMinutes')}/></Field>
        <Field label="سعر كل شريحة إضافية (ل.س)"><input type="number" value={f.blockPrice} onChange={set('blockPrice')}/></Field>
        <Field label="المدة المعتادة للزيارة (للتقدير)"><input type="number" value={f.expectedMinutes} onChange={set('expectedMinutes')}/></Field>
        <Field label="تقريب الفاتورة لأعلى إلى مضاعف"><input type="number" value={f.roundingStep} onChange={set('roundingStep')}/></Field>
        <Field label="عمولة المنصة (نقطة أساس: 2000 = 20%)"><input type="number" value={f.commissionBps} onChange={set('commissionBps')}/></Field>
        <Field label="ترتيب العرض"><input type="number" value={f.sortOrder} onChange={set('sortOrder')}/></Field>
      </div>
      <div className="preview"><b>معاينة الحساب:</b> {[20, 30, 45, 60, 90].map(m => <span key={m}>{m} د ← {n(rounded(m))} ل.س</span>)}</div>
      <div className="actions"><button className="pill on" onClick={() => void save()}>{f.id ? 'حفظ التعديل' : 'إضافة الخدمة'}</button>{f.id && <button className="pill" onClick={() => setF(blank)}>إلغاء التعديل</button>}</div>
      {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}{err && <p className="hint err">{err}</p>}
    </Panel>
    <Panel title="الخدمات المعروضة">
      <Table head={['الخدمة', 'السعر الأساسي', 'الشريحة الإضافية', 'ظاهرة للمرضى', 'معتمدة سريريًا', '']} rows={items.map(s => [
        <><b>{s.title_ar}</b><br/><small className="hint" dir="ltr">{s.code}</small></>,
        `${n(s.price_amount)} / ${s.included_minutes} د`, `${n(s.block_price)} / ${s.block_minutes} د`,
        <button className={'pill ' + (s.active ? 'on' : '')} onClick={() => void toggle(s, 'active')}>{s.active ? 'ظاهرة' : 'مخفية'}</button>,
        <button className={'pill ' + (s.dispatch_approved ? 'on' : '')} onClick={() => void toggle(s, 'dispatchApproved')}>{s.dispatch_approved ? 'معتمدة' : 'غير معتمدة'}</button>,
        <button className="pill" onClick={() => edit(s)}>تعديل</button>])}/>
    </Panel>
    <Notice>تظهر الخدمة للمرضى فقط إذا كانت «ظاهرة» و«معتمدة سريريًا» معًا. اعتماد الخدمة قرار سريري/قانوني، فلا تفعّله إلا بموافقة المسؤول السريري. تغيير السعر لا يمس الطلبات الجارية: لكل طلب نسخة سعر ثابتة وقت إنشائه.</Notice>
  </>;
}

export function Promos({live}: {live: Live}) {
  const {data, err, load} = useApi(live, '/v1/admin/promos');
  const blank = {code: '', description: '', type: 'PERCENT', value: '', maxDiscount: '', minAmount: '', validTo: '', maxRedemptions: '', perUserLimit: '1', firstOrderOnly: false};
  const [f, setF] = useState<any>(blank);
  const [msg, setMsg] = useState('');
  if (!live) return <NeedLogin title="أكواد الخصم"/>;
  const set = (k: string) => (e: any) => setF((p: any) => ({...p, [k]: e.target.type === 'checkbox' ? e.target.checked : e.target.value}));
  async function create() {
    setMsg('');
    try {
      const b: any = {code: f.code.trim(), type: f.type, value: Number(f.value), perUserLimit: Number(f.perUserLimit || 1), firstOrderOnly: f.firstOrderOnly};
      if (f.description) b.description = f.description;
      if (f.maxDiscount) b.maxDiscount = Number(f.maxDiscount);
      if (f.minAmount) b.minAmount = Number(f.minAmount);
      if (f.maxRedemptions) b.maxRedemptions = Number(f.maxRedemptions);
      if (f.validTo) b.validTo = new Date(f.validTo + 'T23:59:59').toISOString();
      await send(live!, 'POST', '/v1/admin/promos', b);
      setMsg('تم إنشاء الكود.'); setF(blank); await load();
    } catch (e) { setMsg(`تعذر الإنشاء: ${msgOf(e)}`); }
  }
  async function toggle(p: any) { try { await send(live!, 'PATCH', `/v1/admin/promos/${p.id}`, {active: !p.active}); await load(); } catch (e) { setMsg(msgOf(e)); } }
  const items: any[] = data?.items ?? [];
  return <>
    <Panel title="إنشاء كود خصم">
      <div className="form">
        <Field label="الكود"><input dir="ltr" value={f.code} onChange={set('code')} placeholder="WELCOME20"/></Field>
        <Field label="النوع"><select value={f.type} onChange={set('type')}><option value="PERCENT">نسبة %</option><option value="FIXED">مبلغ ثابت</option></select></Field>
        <Field label={f.type === 'PERCENT' ? 'النسبة (1-100)' : 'المبلغ (ل.س)'}><input type="number" value={f.value} onChange={set('value')}/></Field>
        <Field label="أقصى خصم (ل.س) — اختياري"><input type="number" value={f.maxDiscount} onChange={set('maxDiscount')}/></Field>
        <Field label="أدنى مبلغ للطلب — اختياري"><input type="number" value={f.minAmount} onChange={set('minAmount')}/></Field>
        <Field label="ينتهي في — اختياري"><input type="date" value={f.validTo} onChange={set('validTo')}/></Field>
        <Field label="أقصى عدد استخدامات كلي — اختياري"><input type="number" value={f.maxRedemptions} onChange={set('maxRedemptions')}/></Field>
        <Field label="مرات الاستخدام لكل مريض"><input type="number" value={f.perUserLimit} onChange={set('perUserLimit')}/></Field>
        <Field label="الوصف"><input value={f.description} onChange={set('description')}/></Field>
      </div>
      <label className="check"><input type="checkbox" checked={f.firstOrderOnly} onChange={set('firstOrderOnly')}/> للطلب الأول فقط (مناسب لكود الترحيب بالمستخدمين الجدد)</label>
      <div className="actions"><button className="pill on" onClick={() => void create()}>إنشاء الكود</button></div>
      {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}{err && <p className="hint err">{err}</p>}
    </Panel>
    <Panel title="الأكواد">
      <Table head={['الكود', 'الخصم', 'الاستخدام', 'إجمالي الخصم الممنوح', 'ينتهي', 'الحالة']} rows={items.map(p => [
        <><b dir="ltr">{p.code}</b><br/><small className="hint">{p.description ?? ''}{p.first_order_only ? ' • للطلب الأول' : ''}</small></>,
        p.type === 'PERCENT' ? `${Number(p.value)}%${p.max_discount ? ` (حتى ${n(p.max_discount)})` : ''}` : `${n(p.value)} ل.س`,
        `${p.used}${p.max_redemptions ? ` / ${p.max_redemptions}` : ''} • حُفظ لدى ${p.claimed}`, `${n(p.discount_given)} ل.س`,
        p.valid_to ? String(p.valid_to).slice(0, 10) : '—',
        <button className={'pill ' + (p.active ? 'on' : '')} onClick={() => void toggle(p)}>{p.active ? 'مفعّل' : 'موقوف'}</button>])}/>
    </Panel>
    <PromoAbuse live={live}/>
    <Notice>يطبّق المريض الكود بإدخاله عند الطلب، أو يحفظه مرة واحدة بعد تثبيت التطبيق فيُطبَّق تلقائيًا على طلبه التالي. تعديل الكود أو إيقافه يؤثر على الطلبات الجديدة فقط.</Notice>
  </>;
}

export function TopNurses({live}: {live: Live}) {
  const [period, setPeriod] = useState('month');
  const {data, err, load} = useApi(live, `/v1/admin/leaderboard?period=${period}`);
  const rewards = useApi(live, '/v1/admin/rewards');
  const [f, setF] = useState<any>({nurseId: '', kind: 'REPUTATION', amount: '', note: ''});
  const [msg, setMsg] = useState('');
  useEffect(() => { void load(); }, [period]);
  if (!live) return <NeedLogin title="المتميزون والمكافآت"/>;
  const periodLabel = period === 'all' ? 'all' : new Date().toISOString().slice(0, 7);
  async function grant() {
    setMsg('');
    try { await send(live!, 'POST', '/v1/admin/rewards', {nurseId: f.nurseId, kind: f.kind, amount: Number(f.amount), period: periodLabel, note: f.note || undefined}); setMsg('سُجّلت المكافأة.'); setF({...f, amount: '', note: ''}); await rewards.load(); }
    catch (e) { setMsg(`تعذر التسجيل: ${msgOf(e)}`); }
  }
  const board = (title: string, rows: any[], cols: [string, (r: any) => string][]) => <Panel title={title}>
    <Table head={['#', 'الممرض', ...cols.map(c => c[0]), '']} rows={(rows ?? []).slice(0, 5).map((r, i) => [i + 1, r.name, ...cols.map(c => c[1](r)),
      <button className="pill" onClick={() => setF({...f, nurseId: r.nurse_id})}>مكافأة</button>])}/></Panel>;
  return <>
    <div className="toolbar panel"><div className="filters">{[['week', 'آخر 7 أيام'], ['month', 'هذا الشهر'], ['all', 'الكل']].map(([k, l]) => <button key={k} className={'pill ' + (period === k ? 'on' : '')} onClick={() => setPeriod(k!)}>{l}</button>)}</div></div>
    {err && <p className="hint err">{err}</p>}
    {board('الأفضل سمعة (تقييم المرضى)', data?.byReputation, [['التقييم المرجّح', r => String(r.reputation)], ['المتوسط', r => String(r.avg_stars ?? '—')], ['عدد التقييمات', r => String(r.reviews)]])}
    {board('الأكثر عملًا (زيارات مكتملة)', data?.byWork, [['الزيارات', r => String(r.visits)], ['قيمة الزيارات', r => `${n(r.revenue)} ل.س`]])}
    {board('الأكثر دخلًا للشركة (عمولة المنصة)', data?.byCompanyRevenue, [['عمولة المنصة', r => `${n(r.commission)} ل.س`], ['الزيارات', r => String(r.visits)]])}
    <Panel title="تسجيل مكافأة">
      <div className="form">
        <Field label="الممرض (اضغط «مكافأة» في أي لائحة)"><input dir="ltr" value={f.nurseId} onChange={e => setF({...f, nurseId: e.target.value})}/></Field>
        <Field label="السبب"><select value={f.kind} onChange={e => setF({...f, kind: e.target.value})}><option value="REPUTATION">سمعة</option><option value="WORK">عمل</option><option value="REVENUE">دخل للشركة</option><option value="OTHER">أخرى</option></select></Field>
        <Field label="المبلغ (ل.س)"><input type="number" value={f.amount} onChange={e => setF({...f, amount: e.target.value})}/></Field>
        <Field label="ملاحظة"><input value={f.note} onChange={e => setF({...f, note: e.target.value})}/></Field>
      </div>
      <div className="actions"><button className="pill on" onClick={() => void grant()}>تسجيل المكافأة</button></div>
      {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}
    </Panel>
    <Panel title="سجل المكافآت"><Table head={['الممرض', 'الفترة', 'السبب', 'المبلغ', 'ملاحظة']} rows={(rewards.data?.items ?? []).map((w: any) => [w.nurse_name, w.period, w.kind, `${n(w.amount)} ل.س`, w.note ?? '—'])}/></Panel>
    <Notice>«الأفضل سمعة» يعتمد متوسطًا مرجّحًا (بايزي) فلا يتفوق ممرض بتقييمين مثاليين على من لديه عشرات التقييمات الممتازة. المكافأة تُسجَّل هنا للتوثيق والصرف يتم خارج النظام حاليًا.</Notice>
  </>;
}
