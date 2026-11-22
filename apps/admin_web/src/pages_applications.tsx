import {useCallback, useEffect, useState} from 'react';
import {getJson, sendJson} from './session';
import type {Live} from './pages';
import {Notice, Panel, Table} from './ui';
import {Modal, Secret, fmtDate, openProtected} from './widgets';
import {toast} from './toast';

const STATUS: Record<string, [string, string]> = {PENDING: ['بانتظار المراجعة', 'warn'], INTERVIEW: ['مقابلة محدّدة', ''], APPROVED: ['معتمد', ''], REJECTED: ['مرفوض', 'bad']};
const KIND: Record<string, string> = {ID: 'الهوية', LICENSE: 'الرخصة', PRACTICE_CERT: 'شهادة المزاولة'};
const when = (v?: string | null) => v ? new Date(v).toLocaleString('ar-SY', {dateStyle: 'medium', timeStyle: 'short'}) : '—';

function Interview({a, onClose, onDone}: {a: any; onClose: () => void; onDone: () => void}) {
  const [at, setAt] = useState(''); const [note, setNote] = useState('');
  return <Modal title={`موعد مقابلة ${a.display_name}`} onClose={onClose}>
    <div className="form one">
      <label>تاريخ ووقت المقابلة<input type="datetime-local" value={at} onChange={e => setAt(e.target.value)}/></label>
      <label>ملاحظة (مكان المقابلة أو طريقتها)<input value={note} onChange={e => setNote(e.target.value)}/></label>
    </div>
    <p className="hint">تواصل مع المتقدم على هاتفه ({a.phone_e164}) لإبلاغه بالموعد.</p>
    <div className="actions"><button className="pill on" disabled={!at} onClick={() => void sendJson('POST', `/v1/admin/applications/${a.id}/interview`, {interviewAt: new Date(at).toISOString(), note: note || undefined}).then(onDone).catch(() => undefined)}>حفظ الموعد</button>
      <button className="pill" onClick={onClose}>إلغاء</button></div>
  </Modal>;
}

function Reject({a, onClose, onDone}: {a: any; onClose: () => void; onDone: () => void}) {
  const [reason, setReason] = useState('');
  return <Modal title={`رفض طلب ${a.display_name}`} onClose={onClose}>
    <div className="form one"><label>سبب الرفض (يُحفظ في السجل)<input value={reason} onChange={e => setReason(e.target.value)}/></label></div>
    <div className="actions"><button className="pill danger" disabled={reason.trim().length < 2} onClick={() => void sendJson('POST', `/v1/admin/applications/${a.id}/reject`, {reason: reason.trim()}).then(onDone).catch(() => undefined)}>تأكيد الرفض</button>
      <button className="pill" onClick={onClose}>إلغاء</button></div>
  </Modal>;
}

export function Applications({live}: {live: Live}) {
  const [items, setItems] = useState<any[] | null>(null); const [status, setStatus] = useState('PENDING'); const [err, setErr] = useState('');
  const [iv, setIv] = useState<any>(null); const [rj, setRj] = useState<any>(null); const [acct, setAcct] = useState<{phone: string; name: string; pw: string} | null>(null);
  const load = useCallback(async () => { try { setItems((await getJson(`/v1/admin/applications${status ? `?status=${status}` : ''}`)).items); setErr(''); } catch (e) { setErr((e as Error).message); } }, [status]);
  useEffect(() => { void load(); }, [load, live.token]);
  const approve = (a: any) => {
    if (!confirm(`اعتماد ${a.display_name}؟ سيُنشأ حساب الدخول فورًا بكلمة المرور الافتراضية ويُجبر على تغييرها عند أول دخول.`)) return;
    void sendJson('POST', `/v1/admin/applications/${a.id}/approve`).then(async r => { setAcct({phone: r.account.phone, name: r.account.name, pw: r.account.defaultPassword}); await load(); await live.reload(); }).catch(() => undefined);
  };
  return <Panel title="طلبات انضمام الممرضين">
    <Notice>لا يُنشأ حساب دخول للمتقدم إلا عند الاعتماد هنا. راجع الهوية والرخصة، حدّد موعد المقابلة، ثم اعتمد أو ارفض.</Notice>
    <div className="toolbar">
      <select value={status} onChange={e => setStatus(e.target.value)}><option value="PENDING">بانتظار المراجعة</option><option value="INTERVIEW">مقابلة محدّدة</option><option value="APPROVED">المعتمدة</option><option value="REJECTED">المرفوضة</option><option value="">الكل</option></select>
    </div>
    {err && <p className="hint err">{err}</p>}
    {items && !items.length && <p className="hint">لا طلبات في هذه الفئة.</p>}
    {items && items.length > 0 && <Table head={['المتقدم', 'الهاتف', 'المحافظة / المنطقة', 'الوثيقة', 'المستندات', 'قُدّم', 'الحالة', '']} rows={items.map(a => [
      <span key="n"><b>{a.display_name}</b>{a.specialty && <small> — {a.specialty}</small>}</span>,
      <span dir="ltr" key="p">{a.phone_e164}</span>, `${a.governorate ?? '—'} / ${a.area ?? '—'}`,
      <span key="d">{a.docKindLabel}: <span dir="ltr">{a.license_ref}</span><br/><small>تنتهي {fmtDate(a.expires_at)}</small></span>,
      <span className="acts" key="f">{a.documents.map((d: any) => <button key={d.id} className="pill" onClick={() => void openProtected(`/v1/admin/application-documents/${d.id}/download`).catch(e => toast.error((e as Error).message))}>{KIND[d.kind] ?? d.kind}</button>)}</span>,
      when(a.created_at),
      <span key="s"><span className={'chip ' + (STATUS[a.status]?.[1] ?? '')}>{STATUS[a.status]?.[0] ?? a.status}</span>{a.interview_at && <small><br/>{when(a.interview_at)}</small>}{a.status === 'REJECTED' && a.staff_note && <small><br/>{a.staff_note}</small>}</span>,
      (a.status === 'PENDING' || a.status === 'INTERVIEW') ? <span className="acts" key="a"><button className="pill" onClick={() => setIv(a)}>موعد المقابلة</button><button className="pill on" onClick={() => approve(a)}>اعتماد وإنشاء الحساب</button><button className="pill danger" onClick={() => setRj(a)}>رفض</button></span> : null])}/>}
    {iv && <Interview a={iv} onClose={() => setIv(null)} onDone={() => { setIv(null); void load(); }}/>}
    {rj && <Reject a={rj} onClose={() => setRj(null)} onDone={() => { setRj(null); void load(); }}/>}
    {acct && <Secret label={`اعتُمد ${acct.name} وأُنشئ حسابه. الهاتف: ${acct.phone} — كلمة المرور الأولى`} value={acct.pw} onClose={() => setAcct(null)}/>}
  </Panel>;
}
