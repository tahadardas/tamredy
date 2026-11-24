import {toast} from './toast';
import {useCallback, useEffect, useRef, useState} from 'react';
import {api, errorAr, getJson, sendJson} from './session';
import type {Live} from './pages';
import {Panel, Table} from './ui';
import {Modal, Secret, fmtDate, openProtected, useBusy} from './widgets';

const KIND: Record<string, string> = {LICENSE: 'رخصة', PRACTICE_CERT: 'شهادة مزاولة المهنة', ID: 'هوية', DEGREE: 'شهادة', PHOTO: 'صورة', OTHER: 'أخرى'};
const LIC: Record<string, [string, string]> = {PENDING: ['بانتظار الاعتماد', 'warn'], APPROVED: ['معتمدة', ''], REJECTED: ['مرفوضة', 'bad'], NEEDS_INFO: ['تحتاج معلومات', 'warn']};
const empty = {phone: '', displayName: '', nurseNo: '', governorateId: '', areaId: '', specialty: '', nationalId: '', notes: ''};
type Gov = {id: string; name: string; areas: {id: string; name: string}[]};
function useRegions() {
  const [g, setG] = useState<Gov[]>([]);
  useEffect(() => { void getJson('/v1/catalog/regions').then(d => setG(d.governorates)).catch(() => undefined); }, []);
  return g;
}

type Extra = {file?: File; docKind: string; licenseRef: string; expiresAt: string; approveNow: boolean};
function NurseForm({initial, onSave, onCancel, isNew}: {initial: typeof empty; isNew: boolean; onSave: (v: any, extra?: Extra) => Promise<void>; onCancel: () => void}) {
  const [f, setF] = useState(initial); const {busy, err, run} = useBusy(); const govs = useRegions();
  const set = (k: string) => (e: any) => setF({...f, [k]: e.target.value});
  const areas = govs.find(x => x.id === f.governorateId)?.areas ?? [];
  const [lic, setLic] = useState({docKind: 'LICENSE', licenseRef: '', expiresAt: '', approveNow: false}); const fileRef = useRef<HTMLInputElement>(null);
  const submit = () => run(async () => {
    const body: any = {displayName: f.displayName.trim()};
    if (f.phone.trim()) body.phone = f.phone.trim();
    if (f.governorateId) body.governorateId = f.governorateId;
    if (f.areaId) body.areaId = f.areaId;
    for (const k of ['specialty', 'nationalId', 'notes'] as const) if (f[k].trim()) body[k] = f[k].trim();
    if (String(f.nurseNo).trim()) body.nurseNo = Number(f.nurseNo);
    const file = fileRef.current?.files?.[0];
    if (isNew && (file || lic.licenseRef || lic.expiresAt) && !(file && lic.licenseRef.trim() && lic.expiresAt)) throw new Error('للرخصة: اختر الملف واكتب رقمها وتاريخ انتهائها معًا، أو اتركها كلها فارغة');
    await onSave(body, isNew ? {file, ...lic, licenseRef: lic.licenseRef.trim()} : undefined);
  });
  return <>
    <div className="form">
      <label>الاسم الكامل<input value={f.displayName} onChange={set('displayName')} placeholder="الاسم الثلاثي للممرض"/></label>
      <label>الهاتف (بصيغة دولية +963...)<input dir="ltr" value={f.phone} onChange={set('phone')} placeholder="+963911000000"/></label>
      <label>رقم الممرض (اتركه فارغًا ليُولَّد تلقائيًا)<input dir="ltr" type="number" value={f.nurseNo} onChange={set('nurseNo')} placeholder="تلقائي"/></label>
      <label>المحافظة<select value={f.governorateId} onChange={e => setF({...f, governorateId: e.target.value, areaId: ''})}><option value="">— اختر المحافظة —</option>{govs.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label>
      <label>المنطقة<select value={f.areaId} disabled={!f.governorateId} onChange={set('areaId')}><option value="">— اختر المنطقة —</option>{areas.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select></label>
      <label>الاختصاص التمريضي<input value={f.specialty} onChange={set('specialty')} placeholder="مثال: تمريض عام، عناية مركزة، أطفال"/></label>
      <label>الرقم الوطني (يُحفظ مشفّرًا){!isNew && ' — اتركه فارغًا لعدم التغيير'}<input dir="ltr" value={f.nationalId} onChange={set('nationalId')} placeholder="11 رقماً وطنيًا"/></label>
      <label style={{gridColumn: '1/-1'}}>ملاحظات وإرشادات داخلية<input value={f.notes} onChange={set('notes')} placeholder="أي ملاحظات إشرافية خاصة بالممرض..."/></label>
    </div>
    {isNew && <>
      <h3>رخصة أو شهادة مزاولة المهنة (اختياري الآن، ويمكن رفعها لاحقًا)</h3>
      <div className="form">
        <label>نوع الوثيقة<select value={lic.docKind} onChange={e => setLic({...lic, docKind: e.target.value})}><option value="LICENSE">رخصة مزاولة المهنة</option><option value="PRACTICE_CERT">شهادة مزاولة المهنة</option></select></label>
        <label>رقم الوثيقة<input dir="ltr" value={lic.licenseRef} onChange={e => setLic({...lic, licenseRef: e.target.value})} placeholder="رقم الرخصة أو الشهادة"/></label>
        <label>تاريخ انتهاء السريان<input type="date" value={lic.expiresAt} onChange={e => setLic({...lic, expiresAt: e.target.value})}/></label>
        <label>ملف الرخصة الممسوح (PDF/JPG/PNG)<input ref={fileRef} type="file" accept="application/pdf,image/jpeg,image/png"/></label>
      </div>
      <label className="check"><input type="checkbox" checked={lic.approveNow} onChange={e => setLic({...lic, approveNow: e.target.checked})}/> اعتماد الرخصة فورًا (أنا راجعتها ودققت صلاحيتها) ليدخل الممرض ويستقبل الطلبات مباشرة</label>
    </>}
    {err && <p className="hint err">{err}</p>}
    <div className="actions"><button className="pill on" disabled={busy} onClick={() => void submit()}>{isNew ? 'إضافة الممرض' : 'حفظ التعديل'}</button><button className="pill" onClick={onCancel}>إلغاء</button></div>
  </>;
}

function Documents({nurseId, docs, reload}: {nurseId: string; docs: any[]; reload: () => Promise<void>}) {
  const [kind, setKind] = useState('LICENSE'); const [title, setTitle] = useState(''); const [ref, setRef] = useState(''); const [exp, setExp] = useState('');
  const file = useRef<HTMLInputElement>(null); const {busy, err, run} = useBusy(); const [ok, setOk] = useState('');
  const upload = () => run(async () => {
    setOk('');
    const f = file.current?.files?.[0];
    if (!f) throw new Error('اختر ملفًا');
    if (f.size > 8 * 1024 * 1024) throw new Error('الملف أكبر من 8 ميغابايت');
    const fd = new FormData(); fd.append('file', f); fd.append('kind', kind);
    if (title) fd.append('title', title);
    if (kind === 'LICENSE' || kind === 'PRACTICE_CERT') { fd.append('licenseRef', ref); fd.append('expiresAt', exp); }
    const r = await api(`/v1/admin/nurses/${nurseId}/documents`, {method: 'POST', body: fd});
    const d = await r.json().catch(() => ({}));
    if (!r.ok) throw new Error(errorAr(d, r.status));
    setOk(d.queuedForApproval ? 'رُفع المستند وأُرسلت الرخصة إلى «اعتماد التراخيص»' : 'رُفع المستند');
    if (file.current) file.current.value = ''; setTitle(''); setRef(''); setExp(''); await reload();
  });
  return <>
    <Table head={['النوع', 'الملف', 'الحجم', 'التاريخ', '']} rows={docs.map(d => [KIND[d.kind] ?? d.kind, d.title || d.original_name, `${Math.ceil(d.size_bytes / 1024)} KB`, fmtDate(d.created_at),
      <span className="acts" key={d.id}><button className="pill" onClick={() => void openProtected(`/v1/admin/documents/${d.id}/download`).catch(e => toast.error((e as Error).message))}>عرض</button>
        <button className="pill danger" onClick={() => { if (confirm('حذف هذا المستند؟')) void sendJson('DELETE', `/v1/admin/documents/${d.id}`).then(reload).catch(e => toast.error((e as Error).message)); }}>حذف</button></span>])}/>
    {!docs.length && <p className="hint">لا مستندات بعد.</p>}
    <h3>رفع مستند جديد</h3>
    <div className="form">
      <label>النوع<select value={kind} onChange={e => setKind(e.target.value)}>{Object.entries(KIND).map(([k, v]) => <option key={k} value={k}>{v}</option>)}</select></label>
      <label>عنوان (اختياري)<input value={title} onChange={e => setTitle(e.target.value)}/></label>
      <label>الملف (PDF/JPG/PNG حتى 8MB)<input ref={file} type="file" accept="application/pdf,image/jpeg,image/png"/></label>
      {(kind === 'LICENSE' || kind === 'PRACTICE_CERT') && <><label>رقم الوثيقة<input dir="ltr" value={ref} onChange={e => setRef(e.target.value)}/></label>
        <label>تاريخ انتهائها<input type="date" value={exp} onChange={e => setExp(e.target.value)}/></label></>}
    </div>
    <p className="hint">الملفات تُخزَّن مشفّرة، ولا يُعرض أي مستند إلا للمشرفين المصرّح لهم ويُسجَّل كل اطلاع. رفع الرخصة مع رقمها وتاريخها يُدخلها طابور الاعتماد (لا تُعتمد تلقائيًا).</p>
    {err && <p className="hint err">{err}</p>}{ok && <p className="hint">{ok}</p>}
    <div className="actions"><button className="pill on" disabled={busy} onClick={() => void upload()}>رفع</button></div>
  </>;
}

function Detail({id, onClose, onChanged}: {id: string; onClose: () => void; onChanged: () => void}) {
  const [p, setP] = useState<any>(null); const [tab, setTab] = useState('info'); const [picked, setPicked] = useState<string[]>([]);
  const {err, run} = useBusy(); const [msg, setMsg] = useState('');
  const load = useCallback(async () => { const d = await getJson(`/v1/admin/nurses/${id}/profile`); setP(d); setPicked(d.skills.filter((s: any) => s.approved).map((s: any) => s.id)); }, [id]);
  useEffect(() => { void load().catch(() => onClose()); }, [load]);
  if (!p) return <Modal title="..." onClose={onClose}><p className="hint">جارٍ التحميل...</p></Modal>;
  return <Modal title={`${p.display_name} — رقم ${p.nurse_no}`} onClose={onClose} maxWidth="840px">
    <div className="tabs">{[['info', 'البيانات'], ['skills', 'المهارات'], ['docs', `المستندات (${p.documents.length})`], ['lic', 'الرخص']].map(([k, l]) =>
      <button key={k} className={'pill ' + (tab === k ? 'on' : '')} onClick={() => setTab(k)}>{l}</button>)}</div>
    {tab === 'info' && <>
      <p className="hint">الرقم الوطني: {p.nationalIdMasked ?? '—'}</p>
      <NurseForm isNew={false} initial={{phone: p.phone_e164, displayName: p.display_name ?? '', nurseNo: String(p.nurse_no), governorateId: p.governorate_id ?? '', areaId: p.area_id ?? '', specialty: p.specialty ?? '', nationalId: '', notes: p.notes ?? ''}}
        onCancel={onClose} onSave={async b => { await sendJson('PATCH', `/v1/admin/nurses/${id}/profile`, b); setMsg('تم الحفظ'); onChanged(); await load(); }}/>
      {msg && <p className="hint">{msg}</p>}</>}
    {tab === 'skills' && <>
      <div className="skills-header">
        <div>
          <h4 style={{margin: '0 0 4px 0', fontSize: '15px', color: 'var(--ink)'}}>المهارات والخدمات السريرية المصرح بها</h4>
          <p className="hint" style={{margin: 0}}>
            تم تفعيل <strong style={{color: '#059669'}}>{picked.length}</strong> من أصل <strong>{p.skills.length}</strong> خدمة. لا يصله طلب لخدمة غير معتمدة هنا.
          </p>
        </div>
        <div style={{display: 'flex', gap: '8px'}}>
          <button type="button" className="pill" onClick={() => setPicked(p.skills.map((s: any) => s.id))}>تحديد الكل</button>
          <button type="button" className="pill" onClick={() => setPicked([])}>إلغاء التحديد</button>
        </div>
      </div>
      <div className="skills-grid">
        {p.skills.map((s: any) => {
          const isChecked = picked.includes(s.id);
          return (
            <div
              key={s.id}
              className={`skill-card ${isChecked ? 'active' : ''}`}
              onClick={() => setPicked(isChecked ? picked.filter((x: any) => x !== s.id) : [...picked, s.id])}
            >
              <div className="skill-card-top">
                <input
                  type="checkbox"
                  checked={isChecked}
                  readOnly
                  style={{cursor: 'pointer', transform: 'scale(1.2)'}}
                />
                <span className={`badge ${isChecked ? 'ok' : 'muted'}`}>
                  {isChecked ? 'مصرح به' : 'غير مفعّل'}
                </span>
              </div>
              <div className="skill-card-body">
                <strong className="skill-card-title">{s.title_ar}</strong>
                <div className="skill-card-meta">
                  {s.price_amount && <span>السعر: {Number(s.price_amount).toLocaleString()} ل.س</span>}
                  {s.requires_prescription && <span style={{color: '#d97706'}}>• تتطلب وصفة</span>}
                </div>
              </div>
            </div>
          );
        })}
      </div>
      {err && <p className="hint err">{err}</p>}
      <div className="actions" style={{marginTop: '16px'}}>
        <button
          className="pill on"
          style={{padding: '10px 24px', fontSize: '14px', fontWeight: 600}}
          onClick={() => void run(async () => {
            await sendJson('PUT', `/v1/admin/nurses/${id}/skills`, {serviceIds: picked});
            setMsg('تم حفظ مهارات الممرض بنجاح وتحديث صلاحيات استقبال الطلبات');
            onChanged();
          })}
        >
          حفظ المهارات المعتمدة ({picked.length})
        </button>
      </div>
      {msg && <p className="hint" style={{color: '#059669', fontWeight: 600}}>{msg}</p>}
    </>}
    {tab === 'docs' && <Documents nurseId={id} docs={p.documents} reload={async () => { await load(); onChanged(); }}/>}
    {tab === 'lic' && <Table head={['النوع', 'رقم الوثيقة', 'تنتهي', 'الحالة', 'ملاحظة']} rows={p.credentials.map((c: any) => [KIND[c.doc_kind] ?? 'رخصة', c.license_ref, fmtDate(c.expires_at), LIC[c.review_status]?.[0] ?? c.review_status, c.review_reason ?? '—'])}/>}
  </Modal>;
}

export function Nurses({live}: {live: Live}) {
  const [items, setItems] = useState<any[] | null>(null); const [q, setQ] = useState(''); const [status, setStatus] = useState('');
  const [gov, setGov] = useState(''); const [areaF, setAreaF] = useState(''); const govs = useRegions();
  const [adding, setAdding] = useState(false); const [open, setOpen] = useState<string | null>(null); const [secret, setSecret] = useState<{pw: string; note?: string} | null>(null); const [err, setErr] = useState('');
  const load = useCallback(async () => {
    try { const p = new URLSearchParams(); if (q) p.set('q', q); if (status) p.set('status', status); if (gov) p.set('governorate', gov); if (areaF) p.set('area', areaF); setItems((await getJson(`/v1/admin/nurses/manage?${p}`)).items); setErr(''); } catch (e) { setErr((e as Error).message); }
  }, [q, status, gov, areaF]);
  useEffect(() => { const t = window.setTimeout(() => void load(), 250); return () => window.clearTimeout(t); }, [load, live.token]);
  const act = (f: () => Promise<unknown>) => f().then(load).catch(() => undefined);
  return <Panel title="إدارة الممرضين">
    <div className="toolbar">
      <input placeholder="بحث بالاسم أو الهاتف أو الرقم" value={q} onChange={e => setQ(e.target.value)}/>
      <select value={status} onChange={e => setStatus(e.target.value)}><option value="">كل الحالات</option><option value="ACTIVE">نشط</option><option value="SUSPENDED">موقوف</option></select>
      <select value={gov} onChange={e => { setGov(e.target.value); setAreaF(''); }}><option value="">كل المحافظات</option>{govs.map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
      <select value={areaF} disabled={!gov} onChange={e => setAreaF(e.target.value)}><option value="">كل المناطق</option>{(govs.find(x => x.id === gov)?.areas ?? []).map(x => <option key={x.id} value={x.id}>{x.name}</option>)}</select>
      <button className="pill on" onClick={() => setAdding(true)}>+ إضافة ممرض</button>
    </div>
    {err && <p className="hint err">{err}</p>}
    {items && <Table head={['الرقم', 'الاسم', 'الهاتف', 'المحافظة', 'المنطقة', 'الرخصة', 'مستندات', 'مهارات', 'التقييم', 'الحالة', '']} rows={items.map(n => [
      n.nurse_no, n.display_name, <span dir="ltr" key="p">{n.phone_e164}</span>, n.governorate ?? '—', n.area ?? '—',
      n.license_status ? <span key="l" className={'chip ' + (LIC[n.license_status]?.[1] ?? '')}>{LIC[n.license_status]?.[0]}</span> : <span key="l" className="chip warn">لا رخصة</span>,
      n.documents, n.skills, n.rating ?? '—', n.account_status === 'ACTIVE' ? 'نشط' : 'موقوف',
      <span className="acts" key="a"><button className="pill" onClick={() => setOpen(n.id)}>فتح</button>
        <button className="pill" onClick={() => act(() => sendJson('POST', `/v1/admin/nurses/${n.id}/status`, {status: n.account_status === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE'}))}>{n.account_status === 'ACTIVE' ? 'إيقاف' : 'تفعيل'}</button>
        <button className="pill" onClick={() => { if (confirm(`استعادة كلمة المرور للممرض ${n.display_name}؟ تحقق أولًا من هوية صاحب الحساب. تصدر كلمة مؤقتة صالحة 30 دقيقة وتنتهي الجلسات الحالية.`)) void sendJson('POST', `/v1/admin/nurses/${n.id}/reset-password`).then(r => setSecret({pw: r.temporaryPassword})).catch(() => undefined); }}>استعادة كلمة المرور</button>
        <button className="pill danger" onClick={() => { if (confirm(`حذف الممرض ${n.display_name}؟ تبقى سجلاته المالية والزيارات محفوظة، ولا يستطيع الدخول بعد ذلك.`)) act(() => sendJson('DELETE', `/v1/admin/nurses/${n.id}/profile`)); }}>حذف</button></span>])}/>}
    {items && !items.length && <p className="hint">لا ممرضين مطابقين.</p>}
    {adding && <Modal title="إضافة كادر تمريضي جديد" onClose={() => setAdding(false)} maxWidth="840px">
      <NurseForm isNew initial={empty} onCancel={() => setAdding(false)} onSave={async (b, x) => {
        const r = await sendJson('POST', '/v1/admin/nurses/manage', b);
        let note = '';
        try {
          if (x?.file) {
            const fd = new FormData(); fd.append('file', x.file); fd.append('kind', x.docKind); fd.append('licenseRef', x.licenseRef); fd.append('expiresAt', x.expiresAt);
            const u = await api(`/v1/admin/nurses/${r.id}/documents`, {method: 'POST', body: fd});
            const ud = await u.json().catch(() => ({}));
            if (!u.ok) throw new Error(errorAr(ud, u.status));
            if (x.approveNow && ud.credentialId) { await sendJson('POST', `/v1/admin/credentials/${ud.credentialId}/decision`, {decision: 'APPROVE'}); note = 'اعتُمدت الرخصة؛ الحساب جاهز للدخول.'; }
            else note = 'رُفعت الرخصة وهي بانتظار الاعتماد في «اعتماد التراخيص».';
          }
        } catch (e) { note = `أُضيف الممرض لكن تعذر رفع الرخصة: ${(e as Error).message}. ارفعها من ملفه.`; }
        setAdding(false); setSecret({pw: r.temporaryPassword, note}); await live.reload(); await load(); setOpen(r.id);
      }}/></Modal>}
    {secret && <Secret label={`كلمة مرور الممرض (يغيّرها عند أول دخول). ${secret.note ?? ''}`} value={secret.pw} onClose={() => setSecret(null)}/>}
    {open && !secret && <Detail id={open} onClose={() => setOpen(null)} onChanged={() => void load()}/>}
  </Panel>;
}
