import {useState, type FormEvent} from 'react';
import {api, getJson, msgOf, sendJson} from './session';

type Hold = {id: string; reference: string; reason: string; released_at: string | null};
type Policy = {policy: {point_days: number; export_days: number} | null; recentRuns: {point_count: number; export_count: number; ran_at: string}[]};
type Evidence = {id: string; sha256: string};

export function SafetyEvidence() {
  const [caseId, setCaseId] = useState('');
  const [exporterId, setExporterId] = useState('');
  const [purpose, setPurpose] = useState('');
  const [recipient, setRecipient] = useState('');
  const [reference, setReference] = useState('');
  const [approvalId, setApprovalId] = useState('');
  const [bundle, setBundle] = useState<Evidence>();
  const [holds, setHolds] = useState<Hold[]>([]);
  const [reason, setReason] = useState('');
  const [policy, setPolicy] = useState<Policy>();
  const [pointDays, setPointDays] = useState('');
  const [exportDays, setExportDays] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const validCase = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(caseId.trim());

  async function run(work: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    setError('');
    try { await work(); }
    catch (error) { setError(msgOf(error)); }
    finally { setBusy(false); }
  }

  function submit(event: FormEvent, work: () => Promise<void>) {
    event.preventDefault();
    void run(work);
  }

  async function loadHolds() {
    setHolds(await getJson(`/v1/admin/safety/events/${caseId.trim()}/legal-holds`));
  }

  async function loadPolicy() {
    const result = await getJson('/v1/admin/safety/retention-policy') as Policy;
    setPolicy(result);
    setPointDays(result.policy ? String(result.policy.point_days) : '');
    setExportDays(result.policy ? String(result.policy.export_days) : '');
  }

  return <section aria-label="الأدلة والحفظ القانوني">
    {error && <p role="alert">{error}</p>}
    <label>معرّف البلاغ <input dir="ltr" disabled={busy} value={caseId} onChange={event => {
      setCaseId(event.currentTarget.value); setHolds([]); setBundle(undefined); setApprovalId('');
    }} /></label>
    <form className="card" onSubmit={event => submit(event, async () => {
      const approval = await sendJson('POST', `/v1/admin/safety/events/${caseId.trim()}/export-approvals`, {
        exporterId: exporterId.trim(), purpose: purpose.trim(), recipient: recipient.trim(),
      });
      setApprovalId(approval.id);
    })}>
      <h2>الموافقة على تصدير الأدلة</h2>
      <label>معرّف موظف التصدير <input dir="ltr" required disabled={busy} value={exporterId} onChange={e => setExporterId(e.currentTarget.value)} /></label>
      <label>الغرض <input required maxLength={240} disabled={busy} value={purpose} onChange={e => setPurpose(e.currentTarget.value)} /></label>
      <label>الجهة المستلمة <input required maxLength={160} disabled={busy} value={recipient} onChange={e => setRecipient(e.currentTarget.value)} /></label>
      <button className="pill" disabled={busy || !validCase}>تسجيل الموافقة</button>
    </form>
    <form className="card" onSubmit={event => submit(event, async () => {
      setBundle(await sendJson('POST', `/v1/admin/safety/events/${caseId.trim()}/export`, {approvalId: approvalId.trim()}));
    })}>
      <h2>حزمة الأدلة</h2>
      <label>معرّف الموافقة <input dir="ltr" required disabled={busy} value={approvalId} onChange={e => {setApprovalId(e.currentTarget.value); setBundle(undefined);}} /></label>
      <button className="pill" disabled={busy || !validCase}>إنشاء الحزمة</button>
      {bundle && <>
        <p>SHA-256 <bdi>{bundle.sha256}</bdi></p>
        <button className="pill" type="button" disabled={busy} onClick={() => void run(async () => {
          const response = await api(`/v1/admin/safety/exports/${bundle.id}`);
          if (!response.ok) throw new Error('تعذر تنزيل الحزمة. تحقق من الصلاحية وسريان الموافقة.');
          const url = URL.createObjectURL(await response.blob());
          const link = document.createElement('a');
          link.href = url;
          link.download = `guardian-evidence-${bundle.id}.json`;
          link.click();
          window.setTimeout(() => URL.revokeObjectURL(url), 1000);
        })}>تنزيل الحزمة</button>
      </>}
    </form>
    <form className="card" onSubmit={event => submit(event, async () => {
      await sendJson('POST', `/v1/admin/safety/events/${caseId.trim()}/legal-holds`, {reason: reason.trim(), reference: reference.trim()});
      setReason(''); setReference(''); await loadHolds();
    })}>
      <h2>الحفظ القانوني للبلاغ</h2>
      <button className="pill" type="button" disabled={busy || !validCase} onClick={() => void run(loadHolds)}>عرض السجل</button>
      <label>مرجع الحفظ <input maxLength={120} disabled={busy} value={reference} onChange={e => setReference(e.currentTarget.value)} /></label>
      <label>سبب الإجراء <input maxLength={240} disabled={busy} value={reason} onChange={e => setReason(e.currentTarget.value)} /></label>
      <button className="pill" disabled={busy || !validCase || !reason.trim() || !reference.trim()}>تفعيل الحفظ</button>
      {holds.map(hold => <p key={hold.id}>{hold.reference} · {hold.reason} · {hold.released_at ? 'منتهٍ' : 'نشط'}
        {!hold.released_at && <button className="pill" type="button" disabled={busy || !reason.trim()} onClick={() => {
          if (!window.confirm('إنهاء الحفظ القانوني لهذا البلاغ؟')) return;
          void run(async () => {
            await sendJson('POST', `/v1/admin/safety/events/${caseId.trim()}/legal-holds/${hold.id}/release`, {reason: reason.trim()});
            setReason(''); await loadHolds();
          });
        }}>إنهاء الحفظ</button>}
      </p>)}
    </form>
    <form className="card" onSubmit={event => submit(event, async () => {
      if (!window.confirm('حفظ مدد الاحتفاظ الجديدة؟')) return;
      await sendJson('POST', '/v1/admin/safety/retention-policy', {pointDays: Number(pointDays), exportDays: Number(exportDays)});
      await loadPolicy();
    })}>
      <h2>سياسة الاحتفاظ</h2>
      <button className="pill" type="button" disabled={busy} onClick={() => void run(loadPolicy)}>عرض السياسة وسجل التنفيذ</button>
      {policy && <>
        {!policy.policy && <p>لا توجد سياسة احتفاظ مسجلة.</p>}
        <label>مدة GPS بالأيام <input type="number" min="1" max="365" required disabled={busy} value={pointDays} onChange={e => setPointDays(e.currentTarget.value)} /></label>
        <label>مدة حزم الأدلة بالأيام <input type="number" min="1" max="365" required disabled={busy} value={exportDays} onChange={e => setExportDays(e.currentTarget.value)} /></label>
        <button className="pill" disabled={busy}>حفظ السياسة</button>
        {policy.recentRuns.map((row, i) => <p key={i}>{new Date(row.ran_at).toLocaleString('ar-SY', {timeZone:'Asia/Damascus'})} · نقاط {row.point_count} · حزم {row.export_count}</p>)}
      </>}
    </form>
  </section>;
}
