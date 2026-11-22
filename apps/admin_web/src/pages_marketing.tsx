import {msgOf} from './session';
import {sendJson} from './session';
import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {Notice, Panel} from './ui';
import {Broadcasts, Packs, QuickPromos} from './pages_marketing2';

export const n = (v: number | string) => Number(v).toLocaleString('en-US');
export const send = (_live: unknown, method: string, path: string, body?: unknown) => sendJson(method, path, body);
export const Field = ({label, children}: {label: string; children: React.ReactNode}) => <label>{label}{children}</label>;
export const Switch = ({on, onChange, label}: {on: boolean; onChange: (v: boolean) => void; label: string}) =>
  <label className="switch"><input type="checkbox" checked={on} onChange={e => onChange(e.target.checked)}/><span className="knob"/><b>{label}</b></label>;
const DAYS = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];

type Feature = {key: string; enabled: boolean; config: any};

/** A card for one marketing feature: its own on/off switch, its values, and a save button. */
function FeatureCard({live, f, title, desc, reload, children}: {live: NonNullable<Live>; f: Feature; title: string; desc: string; reload: () => Promise<void>;
  children?: ((cfg: any, set: (k: string, v: any) => void) => React.ReactNode) | React.ReactNode}) {
  const hasCfg = typeof children === 'function';
  const [cfg, setCfg] = useState<any>(f.config);
  const [msg, setMsg] = useState('');
  useEffect(() => setCfg(f.config), [f.config]);
  const set = (k: string, v: any) => setCfg((p: any) => ({...p, [k]: v}));
  async function save(enabled?: boolean) {
    setMsg('');
    try { await send(live, 'PUT', `/v1/admin/marketing/${f.key}`, {...(enabled !== undefined ? {enabled} : {}), ...(children ? {config: cfg} : {})}); await reload(); setMsg('تم الحفظ'); }
    catch (e) { setMsg(`تعذر الحفظ: ${msgOf(e)}`); }
  }
  return <Panel title={title}>
    <Switch on={f.enabled} onChange={v => void save(v)} label={f.enabled ? 'مفعّلة' : 'غير مفعّلة'}/>
    <p className="hint">{desc}</p>
    {hasCfg && <>{(children as any)(cfg, set)}<div className="actions"><button className="pill on" onClick={() => void save()}>حفظ القيم</button></div></>}
    {!hasCfg && children}
    {msg && <p className={'hint ' + (msg.startsWith('تعذر') ? 'err' : '')}>{msg}</p>}
  </Panel>;
}

export function Marketing({live}: {live: Live}) {
  const [data, setData] = useState<any>(null);
  const [err, setErr] = useState('');
  const [referral, setReferral] = useState<boolean | null>(null);
  const load = async () => {
    if (!live) return;
    try { setData(await live.get('/v1/admin/marketing')); setReferral((await live.get('/v1/admin/pricing-settings')).settings.referral_enabled); setErr(''); } catch (e) { setErr(msgOf(e)); }
  };
  useEffect(() => { void load(); }, [live?.token]);
  if (!live) return <Panel title="التسويق"><p className="hint">سجّل الدخول (أيقونة الاتصال أعلى الصفحة) بحساب إدارة لإدارة التسويق.</p></Panel>;
  if (!data) return <Panel title="التسويق"><p className="hint">{err || 'جارٍ التحميل...'}</p></Panel>;
  const F = (k: string): Feature => data.features.find((x: Feature) => x.key === k);
  const s = data.stats;
  const Days = ({cfg, set}: {cfg: any; set: (k: string, v: any) => void}) => <div className="preview"><b>الأيام:</b>{DAYS.map((d, i) =>
    <label key={i} className="check"><input type="checkbox" checked={(cfg.days ?? []).includes(i)} onChange={() => set('days', (cfg.days ?? []).includes(i) ? cfg.days.filter((x: number) => x !== i) : [...(cfg.days ?? []), i])}/> {d}</label>)}</div>;
  const inp = (cfg: any, set: any, k: string, label: string, type = 'number') => <Field label={label}><input type={type} value={cfg[k] ?? ''} onChange={e => set(k, type === 'number' ? (e.target.value === '' ? '' : Number(e.target.value)) : e.target.value)}/></Field>;
  return <>
    <div className="stats">
      <div className="stat"><span>مرضى وافقوا على الرسائل التسويقية</span><strong>{s.opted_in}</strong></div>
      <div className="stat"><span>طلبات بخصم تلقائي (30 يومًا)</span><strong>{s.auto_discount_orders_30d}</strong></div>
      <div className="stat"><span>أكواد استرجاع أُرسلت (30 يومًا)</span><strong>{s.winback_30d}</strong></div>
      <div className="stat"><span>باقات سارية</span><strong>{s.active_packs}</strong></div>
    </div>
    <Notice>كل ميزة هنا تُفعَّل وتُلغى بمفتاحها. الميزات الترويجية مُعطَّلة افتراضيًا. الخصم التلقائي الواحد فقط يُطبَّق على الطلب (الأكبر نسبة)، والكود الذي يكتبه المريض يتقدّم عليه.</Notice>

    <QuickPromos live={live}/>

    <FeatureCard live={live} f={F('offpeak')} reload={load} title="خصم الأوقات الهادئة" desc="خصم تلقائي بلا كود عندما يُنشأ الطلب في الأيام والساعات التي تحددها (بتوقيت دمشق) لتوزيع الحمل.">
      {(cfg, set) => <><div className="form">{inp(cfg, set, 'percent', 'نسبة الخصم %')}{inp(cfg, set, 'start', 'من (HH:MM)', 'text')}{inp(cfg, set, 'end', 'إلى (HH:MM)', 'text')}{inp(cfg, set, 'maxDiscount', 'أقصى خصم (ل.س)')}</div><Days cfg={cfg} set={set}/></>}
    </FeatureCard>

    <FeatureCard live={live} f={F('loyalty')} reload={load} title="مكافأة الولاء" desc="كل طلب رقم N (محسوبًا على طلباته المدفوعة) يحصل تلقائيًا على خصم.">
      {(cfg, set) => <div className="form">{inp(cfg, set, 'everyN', 'كل كم طلب (مثلًا 5)')}{inp(cfg, set, 'percent', 'نسبة الخصم %')}{inp(cfg, set, 'maxDiscount', 'أقصى خصم (ل.س)')}</div>}
    </FeatureCard>

    <Packs live={live} feature={F('packs')} reload={load} Card={FeatureCard}/>

    <FeatureCard live={live} f={F('winback')} reload={load} title="استرجاع العملاء" desc="يفحص العامل كل 6 ساعات المرضى (الموافقين على التسويق) الذين طلبوا سابقًا وانقطعوا، فيمنح كلًّا كودًا شخصيًا لمرة واحدة ويرسل إشعارًا. مرة واحدة لكل فترة انقطاع.">
      {(cfg, set) => <div className="form">{inp(cfg, set, 'inactiveDays', 'انقطاع (أيام)')}{inp(cfg, set, 'percent', 'نسبة الخصم %')}{inp(cfg, set, 'validDays', 'صلاحية الكود (أيام)')}{inp(cfg, set, 'maxDiscount', 'أقصى خصم')}{inp(cfg, set, 'maxPerRun', 'أقصى عدد لكل دورة')}</div>}
    </FeatureCard>

    <FeatureCard live={live} f={F('badge')} reload={load} title="شارة «ممرض مميز»" desc="تظهر للمريض على شاشة التتبع مع تقييم الممرض إذا بلغ التقييم المرجّح وعدد التقييمات الحدّين أدناه.">
      {(cfg, set) => <div className="form">{inp(cfg, set, 'minReputation', 'أدنى تقييم مرجّح (1-5)')}{inp(cfg, set, 'minReviews', 'أدنى عدد تقييمات')}</div>}
    </FeatureCard>

    <Panel title="برنامج الإحالة (كود شخصي لكل مريض)">
      <Switch on={!!referral} onChange={async v => { try { await send(live, 'PUT', '/v1/admin/pricing-settings', {referralEnabled: v}); await load(); } catch (e) { setErr(msgOf(e)); } }} label={referral ? 'مفعّل' : 'غير مفعّل'}/>
      <p className="hint">قيم الخصومات والسقوف في «الرسوم والضرائب» ← الإحالة.</p>
    </Panel>

    <FeatureCard live={live} f={F('alarm')} reload={load} title="إنذار الطلبات للممرضين" desc="عند وصول طلب جديد يرنّ هاتف كل ممرض قريب (ضمن موجة البحث) بنغمة تمريضي المميزة لمدة العرض، حتى مع إغلاق التطبيق أو قفل الشاشة. عند الإلغاء يصل الطلب إشعارًا عاديًا. يلزم تفعيل الإشعارات (FCM) وإذن الإشعارات على هاتف الممرض."/>

    <Broadcasts live={live} feature={F('broadcasts')} reload={load} Card={FeatureCard}/>
    {err && <p className="hint err">{err}</p>}
  </>;
}
