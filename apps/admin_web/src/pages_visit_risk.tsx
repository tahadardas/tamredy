import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';

const decisions = {CLEAR: 'رفع القيد', HOLD: 'إيقاف التوزيع مؤقتًا', REQUIRE_COMPANION: 'اشتراط مرافق'};
const bases = {VERIFIED_INCIDENT: 'حادثة مثبتة', DOCUMENTED_THREAT: 'تهديد موثّق', INFORMATION_MISMATCH: 'عدم تطابق معلومات', SOLO_WORK: 'ضوابط العمل المنفرد', REASSESSMENT: 'إعادة تقييم'};
type Decision = keyof typeof decisions;
type Basis = keyof typeof bases;
type Queue = {
  requests: {id: string; status: 'SCHEDULED' | 'OFFERING'; title_ar: string; appointment_at?: string | null; decision?: Decision; effective_until?: string | null}[];
  nurses: {id: string; display_name: string | null}[];
};
const clock = new Intl.DateTimeFormat('ar-SY', {timeZone: 'Asia/Damascus', dateStyle: 'medium', timeStyle: 'short'});

export function VisitRisk() {
  const [queue, setQueue] = useState<Queue>();
  const [requestId, setRequestId] = useState('');
  const [decision, setDecision] = useState<Decision>('HOLD');
  const [basis, setBasis] = useState<Basis>('REASSESSMENT');
  const [reference, setReference] = useState('');
  const [hours, setHours] = useState(2);
  const [nurseId, setNurseId] = useState('');
  const [companionId, setCompanionId] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    try { setQueue(await getJson('/v1/admin/safety/review-queue')); setError(''); }
    catch (error) { setError(msgOf(error)); setQueue(undefined); }
  }

  useEffect(() => { void load(); }, []);

  async function submit(event: FormEvent, operation: 'risk' | 'companion') {
    event.preventDefault();
    if (!requestId || busy) return;
    setBusy(true);
    try {
      await sendJson('POST', `/v1/admin/safety/requests/${requestId}/${operation}`, operation === 'risk'
        ? {decision, basis, reference: reference.trim(), effectiveUntil: new Date(Date.now() + hours * 3600000).toISOString()}
        : {nurseId, companionId});
      await load();
    } catch (error) {
      setError(msgOf(error));
    } finally {
      setBusy(false);
    }
  }

  const selected = queue?.requests.find(row => row.id === requestId);
  return <section className="card" aria-label="مراجعة مخاطر الزيارات">
    {error && <p role="alert">{error}</p>}
    <button className="pill" disabled={busy} onClick={() => void load()}>تحديث الزيارات</button>
    {queue && <label>الزيارة <select value={selected?.id ?? ''} onChange={e => setRequestId(e.currentTarget.value)}>
      <option value="">اختر زيارة</option>
      {queue.requests.map(row => <option key={row.id} value={row.id}>
        {row.title_ar} · {row.appointment_at ? clock.format(new Date(row.appointment_at)) : 'توزيع فوري'} · {row.id.slice(0,8)}
      </option>)}
    </select></label>}
    {selected && queue && <>
      {selected.decision && selected.effective_until && <p>آخر مراجعة {decisions[selected.decision]} · حتى {clock.format(new Date(selected.effective_until))}</p>}
      <form onSubmit={event => void submit(event,'risk')}>
        <fieldset disabled={busy}>
          <legend>قرار مراجعة السلامة</legend>
          <label>الإجراء <select value={decision} onChange={e => setDecision(e.currentTarget.value as Decision)}>
            {Object.entries(decisions).map(([key,label]) => <option key={key} value={key}>{label}</option>)}
          </select></label>
          <label>السبب الموثّق <select value={basis} onChange={e => setBasis(e.currentTarget.value as Basis)}>
            {Object.entries(bases).map(([key,label]) => <option key={key} value={key}>{label}</option>)}
          </select></label>
          <label>مرجع المراجعة <input maxLength={120} required value={reference} onChange={e => setReference(e.currentTarget.value)} /></label>
          <label>مدة القرار بالساعات <input type="number" min="1" max="167" required value={hours} onChange={e => setHours(e.currentTarget.valueAsNumber)} /></label>
          <button className="pill" disabled={!reference.trim()} type="submit">تسجيل القرار</button>
        </fieldset>
      </form>
      <form onSubmit={event => void submit(event,'companion')}>
        <fieldset disabled={busy}>
          <legend>ترشيح مرافق مهني</legend>
          {([['الكادر المرشّح',nurseId,setNurseId],['المرافق',companionId,setCompanionId]] as const).map(([label,value,change]) =>
            <label key={label}>{label} <select required value={value} onChange={e => change(e.currentTarget.value)}>
              <option value="">اختر من الكادر المعتمد</option>
              {queue.nurses.map(row => <option key={row.id} value={row.id}>{row.display_name ?? row.id}</option>)}
            </select></label>)}
          <button className="pill" disabled={!nurseId || !companionId || nurseId === companionId} type="submit">طلب تأكيد المرافقة</button>
        </fieldset>
      </form>
    </>}
  </section>;
}
