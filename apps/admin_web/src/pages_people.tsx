import {toast} from './toast';
import {useCallback, useEffect, useState} from 'react';
import {getJson, sendJson} from './session';
import type {Live} from './pages';
import {Notice, Panel, Table} from './ui';
import {Modal, Secret, fmtDate, openProtected, useBusy} from './widgets';

export {Nurses} from './pages_nurses';

const ROLE: Record<string, string> = {PATIENT: 'مريض', ADMIN: 'مدير', CLINICAL_REVIEWER: 'مراجع سريري', NURSE: 'ممرض'};

function NewAccount({onClose, onDone}: {onClose: () => void; onDone: (pw: string) => void}) {
  const [f, setF] = useState({role: 'PATIENT', displayName: '', phone: '', beneficiaryName: ''}); const {busy, err, run} = useBusy();
  return <Modal title="إضافة حساب" onClose={onClose}>
    <div className="form">
      <label>النوع<select value={f.role} onChange={e => setF({...f, role: e.target.value})}><option value="PATIENT">مريض</option><option value="CLINICAL_REVIEWER">مراجع سريري</option><option value="ADMIN">مدير</option></select></label>
      <label>الاسم<input value={f.displayName} onChange={e => setF({...f, displayName: e.target.value})}/></label>
      <label>الهاتف (+963...)<input dir="ltr" value={f.phone} onChange={e => setF({...f, phone: e.target.value})}/></label>
      {f.role === 'PATIENT' && <label>اسم المستفيد الأول (اختياري)<input value={f.beneficiaryName} onChange={e => setF({...f, beneficiaryName: e.target.value})}/></label>}
    </div>
    <p className="hint">الممرضون يُضافون من صفحة «الممرضون». تُولَّد كلمة مرور مؤقتة تُعرض مرة واحدة.</p>
    {err && <p className="hint err">{err}</p>}
    <div className="actions"><button className="pill on" disabled={busy} onClick={() => void run(async () => {
      const b: any = {role: f.role, displayName: f.displayName.trim(), phone: f.phone.trim()}; if (f.role === 'PATIENT' && f.beneficiaryName.trim()) b.beneficiaryName = f.beneficiaryName.trim();
      onDone((await sendJson('POST', '/v1/admin/users', b)).temporaryPassword);
    })}>إنشاء</button><button className="pill" onClick={onClose}>إلغاء</button></div>
  </Modal>;
}

function EditStaff({u, onClose, onDone}: {u: any; onClose: () => void; onDone: () => void}) {
  const [f, setF] = useState({displayName: u.display_name ?? '', phone: u.phone_e164, role: u.role}); const {busy, err, run} = useBusy();
  return <Modal title="تعديل حساب إداري" onClose={onClose}>
    <div className="form">
      <label>الاسم<input value={f.displayName} onChange={e => setF({...f, displayName: e.target.value})}/></label>
      <label>الهاتف<input dir="ltr" value={f.phone} onChange={e => setF({...f, phone: e.target.value})}/></label>
      <label>الصلاحية<select value={f.role} onChange={e => setF({...f, role: e.target.value})}><option value="ADMIN">مدير</option><option value="CLINICAL_REVIEWER">مراجع سريري</option></select></label>
    </div>
    <p className="hint">تغيير الصلاحية يُنهي جلسات الحساب الحالية.</p>
    {err && <p className="hint err">{err}</p>}
    <div className="actions"><button className="pill on" disabled={busy} onClick={() => void run(async () => { await sendJson('PATCH', `/v1/admin/staff/${u.id}`, f); onDone(); })}>حفظ</button></div>
  </Modal>;
}

export function Accounts({live}: {live: Live}) {
  const [tab, setTab] = useState<'PATIENT' | 'NURSE' | 'STAFF'>('PATIENT'); const [items, setItems] = useState<any[] | null>(null);
  const [adding, setAdding] = useState(false); const [secret, setSecret] = useState<string | null>(null); const [edit, setEdit] = useState<any>(null); const [err, setErr] = useState('');
  const [page, setPage] = useState(1);
  const [more, setMore] = useState(false);
  const [revision, refresh] = useState(0);
  const [working, setWorking] = useState(false);
  const [deleting, setDeleting] = useState<any>(null);
  useEffect(() => {
    let current = true;
    setItems(null);
    setErr('');
    setMore(false);
    const path = tab === 'STAFF' ? '/v1/admin/staff' : `/v1/admin/users?role=${tab}&page=${page}`;
    getJson(path).then(result => {
      if (current) {setItems(result.items);setMore(Boolean(result.hasMore));}
    }).catch(e => {if (current) setErr((e as Error).message);});
    return () => {current = false;};
  }, [tab,page,revision,live.token]);
  const load = () => refresh(n => n + 1);
  const act = async (f: () => Promise<any>, after?: (r: any) => void) => {
    setWorking(true); setErr('');
    try { const result = await f(); after?.(result); load(); }
    catch (e) {setErr((e as Error).message);}
    finally {setWorking(false);}
  };
  return <Panel title="الحسابات">
    <div className="toolbar">
      <button className={'pill ' + (tab === 'PATIENT' ? 'on' : '')} onClick={() => {setTab('PATIENT');setPage(1);}}>المرضى</button>
      <button className={'pill ' + (tab === 'NURSE' ? 'on' : '')} onClick={() => {setTab('NURSE');setPage(1);}}>الممرضون</button>
      <button className={'pill ' + (tab === 'STAFF' ? 'on' : '')} onClick={() => {setTab('STAFF');setPage(1);}}>المشرفون والمراجعون</button>
      <button className="pill on" onClick={() => setAdding(true)}>+ إضافة حساب</button>
    </div>
    {err && <p className="hint err">{err}</p>}
    {items && <Table head={['الاسم', 'الهاتف', 'النوع', 'الحالة', 'منذ', '']} rows={items.map(u => [u.display_name ?? '—', <span dir="ltr" key="p">{u.phone_e164}</span>, ROLE[u.role] ?? u.role,
      u.status === 'ACTIVE' ? (u.locked_until && new Date(u.locked_until) > new Date() ? 'مقفل مؤقتًا' : 'نشط') : 'موقوف', fmtDate(u.created_at),
      <span className="acts" key="a">
        {tab === 'STAFF' && <button className="pill" onClick={() => setEdit(u)}>تعديل</button>}
        <button className="pill" disabled={working} onClick={() => { if (confirm('هل تحققت من هوية صاحب الحساب؟ تصدر كلمة مؤقتة صالحة 30 دقيقة وتنتهي الجلسات الحالية.')) void act(() => sendJson('POST', `/v1/admin/users/${u.id}/reset-password`), r => setSecret(r.temporaryPassword)); }}>كلمة مرور جديدة</button>
        <button className="pill" disabled={working} onClick={() => void act(() => sendJson('POST', `/v1/admin/users/${u.id}/status`, {status: u.status === 'ACTIVE' ? 'SUSPENDED' : 'ACTIVE'}))}>{u.status === 'ACTIVE' ? 'إيقاف' : 'تفعيل'}</button>
        <button className="pill danger" disabled={working} onClick={() => {setErr('');setDeleting(u);}}>حذف</button></span>])}/>}
    {items?.length === 0 && <p>لا توجد حسابات في هذه الصفحة.</p>}
    {tab !== 'STAFF' && <div className="actions">
      <button className="pill" disabled={page === 1 || working} onClick={() => setPage(n => n - 1)}>السابق</button>
      <button className="pill" disabled={!more || working} onClick={() => setPage(n => n + 1)}>التالي</button>
    </div>}
    {deleting && <Modal title={`حذف حساب ${deleting.display_name ?? deleting.phone_e164}`} onClose={() => {if (!working) setDeleting(null);}}>
      <p>سيُغلق الحساب وتنتهي جلساته ويُحرّر رقم الهاتف. يبقى سجل الطلبات والتدقيق محفوظًا.</p>
      {err && <p className="err" role="alert">{err}</p>}
      <button className="pill danger" disabled={working} onClick={() => void act(
        () => sendJson('DELETE', `/v1/admin/users/${deleting.id}`), () => setDeleting(null),
      )}>تأكيد الحذف</button>
    </Modal>}
    {adding && <NewAccount onClose={() => setAdding(false)} onDone={pw => { setAdding(false); setSecret(pw); void load(); }}/>}
    {edit && <EditStaff u={edit} onClose={() => setEdit(null)} onDone={() => { setEdit(null); void load(); }}/>}
    {secret && <Secret label="كلمة المرور" value={secret} onClose={() => setSecret(null)}/>}
  </Panel>;
}

export function Credentials({live}: {live: Live}) {
  const [acct, setAcct] = useState<{phone: string; name: string; pw: string} | null>(null);
  const [items, setItems] = useState<any[] | null>(null); const [err, setErr] = useState(''); const [reason, setReason] = useState<Record<string, string>>({});
  const load = useCallback(async () => { try { setItems((await getJson('/v1/admin/credentials/pending')).items); setErr(''); } catch (e) { setErr((e as Error).message); } }, []);
  useEffect(() => { void load(); }, [load, live.token]); // always fresh when the page opens
  const decide = (id: string, decision: string) => {
    if (decision !== 'APPROVE' && !reason[id]?.trim()) return toast.error('اكتب سبب الرفض أو طلب المعلومات');
    void sendJson('POST', `/v1/admin/credentials/${id}/decision`, {decision, reason: reason[id]}).then(async (r: any) => {
      await load(); await live.reload();
      const a = r.account;
      if (decision !== 'APPROVE') return;
      if (a?.usingDefaultPassword) setAcct({phone: a.phone, name: a.name, pw: a.defaultPassword});
      else toast.ok(`اعتُمدت الرخصة. ${a?.name ?? 'الممرض'} يدخل التطبيق برقم هاتفه وكلمة المرور التي اختارها.`);
    }).catch(() => undefined);
  };
  return <Panel title="اعتماد التراخيص">
    {acct && <Secret label={`اعتُمدت الرخصة وحساب ${acct.name ?? 'الممرض'} جاهز للدخول. الهاتف: ${acct.phone} — كلمة المرور الأولى`} value={acct.pw} onClose={() => setAcct(null)}/>}
    <Notice>افتح مستند الرخصة وقارنه برقمها وتاريخها قبل الاعتماد. لا يستقبل الممرض طلبات قبل اعتماد رخصته.</Notice>
    {err && <p className="hint err">{err}</p>}
    {items && !items.length && <p className="hint">لا رخص بانتظار المراجعة.</p>}
    {items && items.length > 0 && <Table head={['الممرض', 'النوع', 'رقم الوثيقة', 'تنتهي', 'المستند', 'السبب (للرفض/الطلب)', '']} rows={items.map(c => [
      `${c.nurse_name ?? '—'} (#${c.nurse_no ?? ''})`, c.doc_kind === 'PRACTICE_CERT' ? 'شهادة مزاولة' : 'رخصة', c.license_ref, fmtDate(c.expires_at),
      c.document_id ? <button key="d" className="pill" onClick={() => void openProtected(`/v1/admin/documents/${c.document_id}/download`).catch(e => toast.error((e as Error).message))}>عرض</button> : <span key="d" className="chip warn">بلا مستند</span>,
      <input key="r" value={reason[c.id] ?? ''} onChange={e => setReason({...reason, [c.id]: e.target.value})}/>,
      <span className="acts" key="a"><button className="pill on" onClick={() => decide(c.id, 'APPROVE')}>اعتماد</button><button className="pill" onClick={() => decide(c.id, 'NEEDS_INFO')}>طلب معلومات</button><button className="pill danger" onClick={() => decide(c.id, 'REJECT')}>رفض</button></span>])}/>}
  </Panel>;
}
