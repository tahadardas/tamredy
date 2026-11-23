import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {msgOf, sendJson} from './session';
import {Panel} from './ui';

type ReviewStatus = 'UNDER_REVIEW' | 'NEEDS_INFORMATION' | 'APPROVED' | 'REJECTED';
type Appeal = {id: string; submitter_role: 'PATIENT' | 'NURSE'; status: string; description: string; created_at: string};
const labels: Record<string, string> = {
  SUBMITTED: 'بانتظار المراجعة', UNDER_REVIEW: 'قيد المراجعة', NEEDS_INFORMATION: 'طلب معلومات إضافية',
  APPROVED: 'قبول الاعتراض', REJECTED: 'رفض الاعتراض',
};

export function CancellationAppeals({live}: {live: Live}) {
  const [appeals, setAppeals] = useState<Appeal[]>([]);
  const [selected, setSelected] = useState<Appeal | null>(null);
  const [reason, setReason] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function load() {
    if (!live) return;
    try {
      const page = await live.get('/v1/admin/cancellation-appeals');
      setAppeals(page.items);
      setError('');
    } catch (cause) {
      setError(msgOf(cause));
    }
  }

  useEffect(() => { void load(); }, [live?.token]);

  async function review(status: ReviewStatus) {
    if (!selected || !reason.trim() || busy) return;
    setBusy(true);
    setError('');
    try {
      await sendJson('POST', `/v1/admin/cancellation-appeals/${selected.id}/review`, {status, reason: reason.trim()});
      setSelected(null);
      setReason('');
      await load();
    } catch (cause) {
      setError(msgOf(cause));
    } finally {
      setBusy(false);
    }
  }

  return <Panel title="اعتراضات الإلغاء">
    {error && <p className="err" role="alert">{error}</p>}
    <button className="pill" onClick={() => void load()} disabled={busy}>تحديث القائمة</button>
    {appeals.length === 0 && <p className="hint">لا توجد اعتراضات في قائمة المراجعة.</p>}
    <ul>
      {appeals.map(item => <li key={item.id}>
        <button className="pill" disabled={busy} onClick={() => {setSelected(item); setReason('');}}>
          {item.submitter_role === 'PATIENT' ? 'مريض' : 'ممرض'} · {labels[item.status]} · {item.created_at.split('T')[0]}
        </button>
      </li>)}
    </ul>
    {selected && <div className="form">
      <p>{selected.description}</p>
      <label>سبب إجراء المراجعة
        <textarea maxLength={2000} value={reason} onChange={event => setReason(event.target.value)} disabled={busy}/>
      </label>
      <div className="actions">
        {(selected.status === 'UNDER_REVIEW'
          ? ['NEEDS_INFORMATION', 'APPROVED', 'REJECTED'] as const
          : ['UNDER_REVIEW'] as const
        ).map(status => <button key={status} className="pill" disabled={busy || !reason.trim()} onClick={() => void review(status)}>
          {status === 'UNDER_REVIEW' ? 'بدء المراجعة' : labels[status]}
        </button>)}
      </div>
    </div>}
  </Panel>;
}
