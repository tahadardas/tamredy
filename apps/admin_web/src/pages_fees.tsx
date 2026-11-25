import {msgOf} from './session';
import {sendJson} from './session';
import {useEffect, useRef, useState} from 'react';
import type {Live} from './pages';
import {Notice, Panel, Table} from './ui';

const n = (v: number | string) => Number(v).toLocaleString('en-US');
function useApi(live: Live, path: string) {
  const [data, setData] = useState<any>(null);
  const [err, setErr] = useState('');
  const load = async () => { if (!live) return; try { setData(await live.get(path)); setErr(''); } catch (e) { setErr(msgOf(e)); } };
  useEffect(() => { void load(); }, [live?.token]);
  return {data, err, load};
}
const send = (_live: unknown, method: string, path: string, body?: unknown) => sendJson(method, path, body);
const NeedLogin = ({title}: {title: string}) => <Panel title={title}><p className="hint">سجّل الدخول (أيقونة الاتصال أعلى الصفحة) بحساب إدارة لإدارة هذه البيانات.</p></Panel>;
const Field = ({label, children}: {label: string; children: React.ReactNode}) => <label>{label}{children}</label>;
const Switch = ({on, onChange, label}: {on: boolean; onChange: (v: boolean) => void; label: string}) =>
  <label className="switch"><input type="checkbox" checked={on} onChange={e => onChange(e.target.checked)}/><span className="knob"/><b>{label}</b></label>;
const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

/** Fees, tax, tips, holidays, commission tiers, referral and promo-protection settings. Each automatic fee has its own on/off switch. */
export function FeesSettings({live}: {live: Live}) {
  const {data, err, load} = useApi(live, '/v1/admin/pricing-settings');
  const [f, setF] = useState<any>(null);
  const [msg, setMsg] = useState('');
  const [hol, setHol] = useState({day: '', name: ''});
  const [tier, setTier] = useState({minReputation: '4.5', minReviews: '20', commissionBps: '1500'});
  useEffect(() => { if (data?.settings) setF(data.settings); }, [data]);
  if (!live) return <NeedLogin title="الرسوم والضرائب"/>;
  if (!f) return <Panel title="الرسوم والضرائب"><p className="hint">{err || 'جارٍ التحميل...'}</p></Panel>;
  const set = (k: string, v: any) => setF((p: any) => ({...p, [k]: v}));
  const num = (k: string) => <input type="number" value={f[k] ?? ''} onChange={e => set(k, e.target.value)}/>;
  async function save() {
    setMsg('');
    const N = (v: any) => Number(v);
    try {
      await send(live!, 'PUT', '/v1/admin/pricing-settings', {
        distanceEnabled: f.distance_enabled, freeKm: N(f.free_km), perKm: N(f.per_km), maxDistanceFee: N(f.max_distance_fee),
        nightEnabled: f.night_enabled, nightStart: f.night_start, nightEnd: f.night_end, nightPercent: N(f.night_percent),
        holidayEnabled: f.holiday_enabled, holidayPercent: N(f.holiday_percent), weekendDays: f.weekend_days.map(Number), stackSurcharges: f.stack_surcharges,
        taxEnabled: f.tax_enabled, taxPercent: N(f.tax_percent), taxLabel: f.tax_label, tipsEnabled: f.tips_enabled, nurseDebtLimit: N(f.nurse_debt_limit),
        referralEnabled: f.referral_enabled, referralReferredPercent: N(f.referral_referred_percent), referralReferrerPercent: N(f.referral_referrer_percent),
        referralMaxDiscount: N(f.referral_max_discount), referralMaxRewardsPerMonth: N(f.referral_max_rewards_per_month),
        promoAttemptsPerHour: N(f.promo_attempts_per_hour), promoMaxOrders30d: N(f.promo_max_orders_30d)});
      setMsg('تم الحفظ. يسري على الطلبات الجديدة؛ الطلبات الجارية تحتفظ بأسعارها.'); await load();
    } catch (e) { setMsg(`تعذر الحفظ: ${msgOf(e)}`); }
  }
  const toggleDay = (d: number) => set('weekend_days', f.weekend_days.includes(d) ? f.weekend_days.filter((x: number) => x !== d) : [...f.weekend_days, d]);
  return <>
    <Panel title="رسم المسافة (تلقائي)">
      <Switch on={f.distance_enabled} onChange={v => set('distance_enabled', v)} label="تفعيل رسم المسافة"/>
      <div className="form"><Field label="كم مجانية (من موقع الممرض إلى المريض)">{num('free_km')}</Field><Field label="سعر الكيلومتر الإضافي (ل.س)">{num('per_km')}</Field><Field label="أقصى رسم مسافة (0 = بلا حد)">{num('max_distance_fee')}</Field></div>
      <p className="hint">تُحسب المسافة تلقائيًا عند قبول الممرض (خط مستقيم × 1.3 تقديرًا للطرق). الرسم كله للممرض ولا تُقتطع منه عمولة.</p>
    </Panel>
    <Panel title="الرسم الليلي (تلقائي)">
      <Switch on={f.night_enabled} onChange={v => set('night_enabled', v)} label="تفعيل الرسم الليلي"/>
      <div className="form"><Field label="يبدأ (HH:MM)"><input dir="ltr" value={f.night_start} onChange={e => set('night_start', e.target.value)}/></Field><Field label="ينتهي (HH:MM)"><input dir="ltr" value={f.night_end} onChange={e => set('night_end', e.target.value)}/></Field><Field label="النسبة % من قيمة الخدمة">{num('night_percent')}</Field></div>
      <p className="hint">يُقاس وقت وصول الممرض بتوقيت دمشق. يجوز أن تتجاوز النافذة منتصف الليل (مثل 22:00 → 06:00).</p>
    </Panel>
    <Panel title="رسم العطلات (تلقائي)">
      <Switch on={f.holiday_enabled} onChange={v => set('holiday_enabled', v)} label="تفعيل رسم العطلات"/>
      <div className="form"><Field label="النسبة % من قيمة الخدمة">{num('holiday_percent')}</Field></div>
      <div className="preview"><b>أيام العطلة الأسبوعية:</b>{DAYS.map((d, i) => <label key={i} className="check"><input type="checkbox" checked={f.weekend_days.includes(i)} onChange={() => toggleDay(i)}/> {d}</label>)}</div>
      <Switch on={f.stack_surcharges} onChange={v => set('stack_surcharges', v)} label="جمع الرسم الليلي والعطلة معًا (وإلا يُطبَّق الأعلى منهما فقط)"/>
      <div className="form" style={{marginTop: 14}}><Field label="تاريخ عطلة رسمية"><input type="date" value={hol.day} onChange={e => setHol({...hol, day: e.target.value})}/></Field><Field label="الاسم"><input value={hol.name} onChange={e => setHol({...hol, name: e.target.value})}/></Field></div>
      <div className="actions"><button className="pill on" onClick={async () => { try { await send(live!, 'POST', '/v1/admin/holidays', hol); setHol({day: '', name: ''}); await load(); } catch (e) { setMsg(msgOf(e)); } }}>إضافة عطلة</button></div>
      <Table head={['التاريخ', 'الاسم', '']} rows={(data?.holidays ?? []).map((h: any) => [h.day, h.name, <button className="pill" onClick={async () => { await send(live!, 'DELETE', `/v1/admin/holidays/${h.day}`); await load(); }}>حذف</button>])}/>
    </Panel>
    <Panel title="الضريبة (تفعيل/إلغاء في أي وقت)">
      <Switch on={f.tax_enabled} onChange={v => set('tax_enabled', v)} label="تفعيل الضريبة على الفاتورة"/>
      <div className="form"><Field label="النسبة %">{num('tax_percent')}</Field><Field label="الاسم الظاهر على الفاتورة"><input value={f.tax_label} onChange={e => set('tax_label', e.target.value)}/></Field></div>
      <p className="hint">تُحسب على المبلغ بعد الخصم وتشمل رسم المسافة، وتظهر بندًا مستقلًا في الفاتورة، ولا تدخل في عمولة الممرض.</p>
    </Panel>
    <Panel title="الإكرامية ومستحقات الشركة">
      <Switch on={f.tips_enabled} onChange={v => set('tips_enabled', v)} label="السماح للمريض بإضافة إكرامية (كلها للممرض)"/>
      <div className="form"><Field label="حد دين الممرض للشركة (0 = بلا حد): يتوقف استقباله للطلبات عند تجاوزه">{num('nurse_debt_limit')}</Field></div>
    </Panel>
    <Panel title="نسبة الممرض المتدرجة حسب تقييمه">
      <div className="form"><Field label="أدنى تقييم مرجّح"><input type="number" step="0.1" value={tier.minReputation} onChange={e => setTier({...tier, minReputation: e.target.value})}/></Field><Field label="أدنى عدد تقييمات"><input type="number" value={tier.minReviews} onChange={e => setTier({...tier, minReviews: e.target.value})}/></Field><Field label="عمولة الشركة (نقطة أساس: 1500 = 15%)"><input type="number" value={tier.commissionBps} onChange={e => setTier({...tier, commissionBps: e.target.value})}/></Field></div>
      <div className="actions"><button className="pill on" onClick={async () => { try { await send(live!, 'POST', '/v1/admin/commission-tiers', {minReputation: Number(tier.minReputation), minReviews: Number(tier.minReviews), commissionBps: Number(tier.commissionBps)}); await load(); } catch (e) { setMsg(msgOf(e)); } }}>إضافة شريحة</button></div>
      <Table head={['من تقييم', 'ومراجعات', 'عمولة الشركة', 'الحالة', '']} rows={(data?.tiers ?? []).map((t: any) => [`${Number(t.min_reputation)}+`, `${t.min_reviews}+`, `${t.commission_bps / 100}%`,
        <button className={'pill ' + (t.active ? 'on' : '')} onClick={async () => { await send(live!, 'PATCH', `/v1/admin/commission-tiers/${t.id}`, {active: !t.active}); await load(); }}>{t.active ? 'مفعّلة' : 'موقوفة'}</button>,
        <button className="pill" onClick={async () => { await send(live!, 'DELETE', `/v1/admin/commission-tiers/${t.id}`); await load(); }}>حذف</button>])}/>
      <p className="hint">الشريحة تُخفّض عمولة الشركة فقط (لا ترفعها فوق عمولة الخدمة). التقييم مرجّح (بايزي) على كل تقييمات المرضى للممرض.</p>
    </Panel>
    <Panel title="كود الإحالة الشخصي">
      <Switch on={f.referral_enabled} onChange={v => set('referral_enabled', v)} label="تفعيل برنامج الإحالة"/>
      <div className="form"><Field label="خصم الصديق الجديد % (طلبه الأول)">{num('referral_referred_percent')}</Field><Field label="مكافأة صاحب الكود % (بعد أول طلب مدفوع لصديقه)">{num('referral_referrer_percent')}</Field><Field label="أقصى خصم (ل.س)">{num('referral_max_discount')}</Field><Field label="أقصى مكافآت لكل مريض شهريًا">{num('referral_max_rewards_per_month')}</Field></div>
    </Panel>
    <Panel title="حماية أكواد الخصم">
      <div className="form"><Field label="أقصى محاولات خاطئة في الساعة">{num('promo_attempts_per_hour')}</Field><Field label="أقصى طلبات بخصم لكل مريض خلال 30 يومًا (0 = بلا حد)">{num('promo_max_orders_30d')}</Field></div>
    </Panel>
    <div className="actions"><button className="pill on" onClick={() => void save()}>حفظ كل الإعدادات</button></div>
    {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}{err && <p className="hint err">{err}</p>}
    <Notice>كل رسم تلقائي مُعطَّل افتراضيًا حتى تفعّله بنفسك وتضع قيمه. تُجمَّد الإعدادات على كل طلب لحظة إنشائه فلا يتغير سعر طلب جارٍ.</Notice>
  </>;
}

export function Dues({live}: {live: Live}) {
  const {data, err, load} = useApi(live, '/v1/admin/dues');
  const [amount, setAmount] = useState<Record<string, string>>({});
  const [msg, setMsg] = useState('');
  const attempts = useRef(new Map<string,string>());
  const inFlight = useRef(new Set<string>());
  if (!live) return <NeedLogin title="مستحقات الشركة"/>;
  const items: any[] = data?.items ?? [];
  async function settle(nurseId: string, direction: 'FROM_NURSE' | 'TO_NURSE') {
    const value=Number(amount[nurseId]);
    if (!Number.isSafeInteger(value) || value<1 || inFlight.current.has(nurseId)) return;
    const attempt=JSON.stringify([nurseId,direction,value]);
    const key=attempts.current.get(attempt) ?? crypto.randomUUID();
    attempts.current.set(attempt,key);
    inFlight.current.add(nurseId);
    setMsg('');
    try {
      await sendJson('POST', `/v1/admin/dues/${nurseId}/settle`,
        {direction,amount:value,note:direction === 'FROM_NURSE' ? 'استلام من الممرض' : 'دفع للممرض'},
        {'Idempotency-Key':key});
      attempts.current.delete(attempt);
      setAmount(current=>({...current,[nurseId]:''}));
      await load();
    }
    catch (e) { setMsg(`تعذر التسجيل: ${msgOf(e)}`); }
    finally { inFlight.current.delete(nurseId); }
  }
  return <>
    <div className="stats three">
      <div className="stat"><span>إجمالي مستحق للشركة على الممرضين</span><strong>{n(data?.totalOwedToCompany ?? 0)}</strong></div>
      <div className="stat"><span>ممرضون عليهم مستحقات</span><strong>{items.filter(i => Number(i.balance) > 0).length}</strong></div>
      <div className="stat"><span>موقوف استقبالهم لتجاوز الحد</span><strong>{items.filter(i => i.blocked).length}</strong></div>
    </div>
    <Panel title="مستحقات الشركة من الممرضين">
      <Table head={['الممرض', 'زيارات مدفوعة', 'الرصيد (+ عليه للشركة / − للشركة عليها)', 'الحالة', 'تسوية']} rows={items.map(i => [i.name, i.visits, <b style={{color: Number(i.balance) > 0 ? '#b12f3e' : '#05866b'}}>{n(i.balance)} ل.س</b>,
        i.blocked ? 'موقوف عن الطلبات' : 'سليم',
        <span className="acts"><input className="amt" type="number" placeholder="المبلغ" value={amount[i.nurse_id] ?? ''} onChange={e => setAmount({...amount, [i.nurse_id]: e.target.value})}/>
          <button className="pill on" onClick={() => void settle(i.nurse_id, 'FROM_NURSE')}>استلمتُ منه</button><button className="pill" onClick={() => void settle(i.nurse_id, 'TO_NURSE')}>دفعتُ له</button></span>])}/>
      {msg && <p className="hint err">{msg}</p>}{err && <p className="hint err">{err}</p>}
    </Panel>
    <Notice>الممرض يقبض نقدًا من المريض ثم يسلّم الشركة حصتها (المبلغ المدفوع − نصيبه). الحساب يعتمد الزيارات المدفوعة بالكامل فقط. إن كان الرصيد سالبًا فالشركة مدينة للممرض (مثلًا عند خصومات كبيرة تتحمّلها الشركة). كل تسوية تُسجَّل في سجل التدقيق.</Notice>
  </>;
}

/** Promo-abuse review: shown inside the promo page. Detection only — you decide what to do. */
export function PromoAbuse({live}: {live: Live}) {
  const {data} = useApi(live, '/v1/admin/promos/abuse');
  if (!live || !data) return null;
  return <Panel title="مراجعة الاشتباه بإساءة الأكواد">
    <p className="hint">عدة حسابات استخدمت أكواد من العنوان نفسه:</p>
    <Table head={['العنوان', 'عدد الحسابات', 'الطلبات', 'الأكواد']} rows={(data.sameAddress ?? []).map((r: any) => [r.address, r.accounts, r.orders, (r.codes ?? []).join('، ')])}/>
    <p className="hint">حسابات خمّنت أكواد (آخر 24 ساعة):</p>
    <Table head={['الحساب', 'محاولات خاطئة']} rows={(data.guessing ?? []).map((r: any) => [r.name, r.failed_attempts])}/>
  </Panel>;
}
