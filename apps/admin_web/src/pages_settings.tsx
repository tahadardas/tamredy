import {useCallback, useEffect, useState} from 'react';
import {getJson, sendJson} from './session';
import type {Live} from './pages';
import {Chip, Notice, Panel, Table} from './ui';
import {useBusy} from './widgets';

function Regions() {
  const [data, setData] = useState<any[]>([]);
  const [gname, setGname] = useState('');
  const [aname, setAname] = useState<Record<string, string>>({});
  const [acoord, setAcoord] = useState<Record<string, {lat?: string; lng?: string}>>({});
  const {err, run} = useBusy();

  const load = useCallback(async () => setData((await getJson('/v1/admin/regions')).governorates), []);
  useEffect(() => { void load().catch(() => undefined); }, [load]);
  const go = (f: () => Promise<unknown>) => run(async () => { await f(); await load(); });

  return (
    <Panel title="المحافظات والمناطق الجغرافية — النطاقات والتغطية">
      <Notice tone="info">
        تظهر المحافظات والمناطق للممرضين والمرضى عند التسجيل واختيار الموقع. للتعطيل أثر مباشر يخفي النطاق عن التسجيل الجديد مع المحافظة التامة على سجلات الزيارات السابقة.
      </Notice>

      {err && <p className="hint err" style={{margin: '12px 0'}}>{err}</p>}

      <div style={{display: 'flex', flexDirection: 'column', gap: '20px', marginTop: '16px'}}>
        {data.map(g => (
          <div
            key={g.id}
            className="card"
            style={{
              padding: '20px',
              background: '#ffffff',
              border: g.active ? '1.5px solid #e2e8f0' : '1.5px dashed #cbd5e1',
              borderRadius: '12px',
              boxShadow: '0 2px 8px rgba(7, 69, 119, 0.04)',
            }}
          >
            {/* Header of Governorate */}
            <div
              style={{
                display: 'flex',
                justifyContent: 'space-between',
                alignItems: 'center',
                flexWrap: 'wrap',
                gap: '12px',
                borderBottom: '1px solid #f1f5f9',
                paddingBottom: '14px',
                marginBottom: '16px',
              }}
            >
              <div style={{display: 'flex', alignItems: 'center', gap: '10px', flexWrap: 'wrap'}}>
                <span style={{fontSize: '20px'}}>🏛️</span>
                <h3 style={{margin: 0, color: g.active ? 'var(--navy)' : '#64748b', fontSize: '18px', fontWeight: 800}}>
                  محافظة {g.name_ar}
                </h3>
                <Chip tone={g.active ? 'success' : 'default'}>
                  {g.active ? 'نطاق فعّال ونشط' : 'نطاق موقوف مؤقتاً'}
                </Chip>
                <Chip tone="info">
                  {g.nurses ?? 0} كادر تمريضي
                </Chip>
                <Chip tone="purple">
                  {g.areas?.length ?? 0} مناطق تابعة
                </Chip>
              </div>

              <div>
                <button
                  className={`pill ${g.active ? 'danger' : 'on'}`}
                  style={{fontSize: '12px', padding: '6px 16px'}}
                  onClick={() => void go(() => sendJson('PATCH', `/v1/admin/regions/governorates/${g.id}`, {active: !g.active}))}
                >
                  {g.active ? 'تعطيل المحافظة' : 'تفعيل المحافظة'}
                </button>
              </div>
            </div>

            {/* Areas Section as Cards Grid */}
            <div>
              <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '10px'}}>
                <h4 style={{margin: 0, color: '#334155', fontSize: '14px', fontWeight: 700}}>
                  المناطق والمربعات الجغرافية ({g.areas?.length ?? 0})
                </h4>
              </div>

              {(!g.areas || g.areas.length === 0) ? (
                <p style={{color: '#94a3b8', fontSize: '13px', margin: '8px 0'}}>لا توجد مناطق مضافة لهذه المحافظة حتى الآن.</p>
              ) : (
                <div
                  style={{
                    display: 'grid',
                    gridTemplateColumns: 'repeat(auto-fill, minmax(210px, 1fr))',
                    gap: '12px',
                    marginBottom: '18px',
                  }}
                >
                  {g.areas.map((a: any) => (
                    <div
                      key={a.id}
                      style={{
                        padding: '12px 14px',
                        background: a.active ? '#f8fafc' : '#f1f5f980',
                        border: a.active ? '1px solid #cbd5e1' : '1px dashed #cbd5e1',
                        borderRadius: '10px',
                        display: 'flex',
                        flexDirection: 'column',
                        justifyContent: 'space-between',
                        gap: '10px',
                        transition: 'all 0.2s ease',
                      }}
                    >
                      <div>
                        <div style={{display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', gap: '6px'}}>
                          <strong style={{fontSize: '14px', color: a.active ? '#0f172a' : '#94a3b8'}}>
                            {a.name_ar}
                          </strong>
                          <span
                            style={{
                              fontSize: '11px',
                              padding: '2px 6px',
                              borderRadius: '6px',
                              background: a.active ? '#e0f2fe' : '#f1f5f9',
                              color: a.active ? '#0369a1' : '#64748b',
                              fontWeight: 600,
                            }}
                          >
                            {a.nurses ? `${a.nurses} ممرض` : '0 ممرض'}
                          </span>
                        </div>

                        <div style={{marginTop: '6px'}}>
                          {a.lat != null && a.lng != null ? (
                            <small style={{color: '#079D90', fontSize: '11px', display: 'flex', alignItems: 'center', gap: '4px'}}>
                              <span>📍</span>
                              <span dir="ltr">{Number(a.lat).toFixed(3)}, {Number(a.lng).toFixed(3)}</span>
                            </small>
                          ) : (
                            <small style={{color: '#d97706', fontSize: '11px', display: 'flex', alignItems: 'center', gap: '4px'}}>
                              <span>⚠️</span> بلا إحداثيات GPS
                            </small>
                          )}
                        </div>
                      </div>

                      <div style={{borderTop: '1px solid #e2e8f0', paddingTop: '8px', display: 'flex', justifyContent: 'space-between', alignItems: 'center'}}>
                        <small style={{fontSize: '11px', color: a.active ? '#059669' : '#94a3b8', fontWeight: 600}}>
                          {a.active ? 'مفعلة بالتطبيق' : 'معطلة'}
                        </small>
                        <button
                          className={`pill ${a.active ? '' : 'on'}`}
                          style={{fontSize: '11px', padding: '3px 10px'}}
                          onClick={() => void go(() => sendJson('PATCH', `/v1/admin/regions/areas/${a.id}`, {active: !a.active}))}
                        >
                          {a.active ? 'تعطيل' : 'تفعيل'}
                        </button>
                      </div>
                    </div>
                  ))}
                </div>
              )}

              {/* Add Area Inline Form inside Governorate Card */}
              <div
                style={{
                  background: '#f8fafc',
                  border: '1px solid #e2e8f0',
                  borderRadius: '10px',
                  padding: '14px 16px',
                  marginTop: '12px',
                }}
              >
                <div style={{fontSize: '13px', fontWeight: 700, color: '#074577', marginBottom: '10px'}}>
                  + إضافة منطقة جديدة تابعة لمحافظة {g.name_ar}
                </div>
                <div style={{display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr)) auto', gap: '10px', alignItems: 'center'}}>
                  <input
                    placeholder="اسم المنطقة (مثال: مشروع دمر)"
                    value={aname[g.id] ?? ''}
                    onChange={e => setAname({...aname, [g.id]: e.target.value})}
                    style={{padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px'}}
                  />
                  <input
                    dir="ltr"
                    placeholder="خط العرض Lat (اختياري)"
                    value={acoord[g.id]?.lat ?? ''}
                    onChange={e => setAcoord({...acoord, [g.id]: {...acoord[g.id], lat: e.target.value}})}
                    style={{padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px'}}
                  />
                  <input
                    dir="ltr"
                    placeholder="خط الطول Lng (اختياري)"
                    value={acoord[g.id]?.lng ?? ''}
                    onChange={e => setAcoord({...acoord, [g.id]: {...acoord[g.id], lng: e.target.value}})}
                    style={{padding: '8px 12px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '13px'}}
                  />
                  <button
                    className="pill on"
                    style={{padding: '8px 18px', fontSize: '13px', whiteSpace: 'nowrap'}}
                    onClick={() => {
                      const n = (aname[g.id] ?? '').trim();
                      if (n) {
                        void go(async () => {
                          const c = acoord[g.id] ?? {};
                          await sendJson('POST', '/v1/admin/regions/areas', {
                            nameAr: n,
                            governorateId: g.id,
                            ...(c.lat && c.lng ? {lat: Number(c.lat), lng: Number(c.lng)} : {}),
                          });
                          setAname({...aname, [g.id]: ''});
                          setAcoord({...acoord, [g.id]: {lat: '', lng: ''}});
                        });
                      }
                    }}
                  >
                    + إضافة المنطقة
                  </button>
                </div>
              </div>
            </div>
          </div>
        ))}

        {/* Add Governorate Dedicated Card */}
        <div
          className="card"
          style={{
            padding: '20px',
            background: 'linear-gradient(135deg, #f8fafc 0%, #edf7f6 100%)',
            border: '1.5px dashed #079D90',
            borderRadius: '12px',
          }}
        >
          <div style={{display: 'flex', alignItems: 'center', gap: '8px', marginBottom: '8px'}}>
            <span style={{fontSize: '18px'}}>➕</span>
            <h4 style={{margin: 0, color: 'var(--navy)', fontSize: '16px', fontWeight: 700}}>
              إضافة محافظة جديدة إلى التغطية الجغرافية
            </h4>
          </div>
          <p style={{margin: '0 0 14px', color: '#64748b', fontSize: '13px'}}>
            أضف اسم المحافظة لتمكينها فوراً وإتاحة تسجيل مناطق وكوادر تمريضية جديدة بها.
          </p>
          <div style={{display: 'flex', gap: '10px', maxWidth: '500px'}}>
            <input
              placeholder="اسم المحافظة (مثال: حلب، حمص، اللاذقية)"
              value={gname}
              onChange={e => setGname(e.target.value)}
              style={{flex: 1, padding: '9px 14px', borderRadius: '8px', border: '1px solid #cbd5e1', fontSize: '14px'}}
            />
            <button
              className="pill on"
              style={{padding: '9px 20px', fontSize: '14px', whiteSpace: 'nowrap'}}
              onClick={() => {
                const n = gname.trim();
                if (n) {
                  void go(async () => {
                    await sendJson('POST', '/v1/admin/regions/governorates', {nameAr: n});
                    setGname('');
                  });
                }
              }}
            >
              + إضافة المحافظة
            </button>
          </div>
        </div>
      </div>
    </Panel>
  );
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
        <label className="check">
          <input type="checkbox" checked={v.pauseAfterTravelCancellation === true} onChange={e => set({...v, pauseAfterTravelCancellation: e.target.checked})}/>
          إيقاف استقبال العروض مؤقتًا للممرض عند إلغاء زيارة في الطريق
        </label>
        <div className="form">
          {([
            ['departureReminderSeconds', 'تذكير بدء التوجه بالثواني (صفر للتعطيل)', 0],
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
