import {useEffect, useState, type FormEvent} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {Chip, Notice, Panel, Table} from './ui';
import {AlertOctagon, CheckCircle2, RefreshCw, ShieldAlert, UserCheck, Users} from 'lucide-react';

const decisions = {
  CLEAR: 'رفع القيد والموافقة الاعتيادية',
  HOLD: 'إيقاف التوزيع مؤقتاً لمراجعة الموقع',
  REQUIRE_COMPANION: 'اشتراط وجود مرافق تمريضي/أمني',
};
const bases = {
  VERIFIED_INCIDENT: 'حادثة سابقة مثبتة في المنطقة',
  DOCUMENTED_THREAT: 'تهديد موثّق أو بلاغ أمني',
  INFORMATION_MISMATCH: 'عدم تطابق معلومات المريض أو العنوان',
  SOLO_WORK: 'ضوابط العمل المنفرد في مناطق نائية',
  REASSESSMENT: 'إعادة تقييم روتينية لمستوى المخاطر',
};
type Decision = keyof typeof decisions;
type Basis = keyof typeof bases;

type Queue = {
  requests: {
    id: string;
    status: 'SCHEDULED' | 'OFFERING';
    title_ar: string;
    appointment_at?: string | null;
    decision?: Decision;
    effective_until?: string | null;
  }[];
  nurses: {id: string; display_name: string | null}[];
};

const clock = new Intl.DateTimeFormat('ar-SY', {
  timeZone: 'Asia/Damascus',
  dateStyle: 'medium',
  timeStyle: 'short',
});

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
    try {
      setQueue(await getJson('/v1/admin/safety/review-queue'));
      setError('');
    } catch (err) {
      setError(msgOf(err));
      setQueue(undefined);
    }
  }

  useEffect(() => {
    void load();
  }, []);

  async function submit(event: FormEvent, operation: 'risk' | 'companion') {
    event.preventDefault();
    if (!requestId || busy) return;
    setBusy(true);
    try {
      await sendJson(
        'POST',
        `/v1/admin/safety/requests/${requestId}/${operation}`,
        operation === 'risk'
          ? {
              decision,
              basis,
              reference: reference.trim(),
              effectiveUntil: new Date(Date.now() + hours * 3600000).toISOString(),
            }
          : {nurseId, companionId},
      );
      await load();
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  const selected = queue?.requests.find(row => row.id === requestId);

  return (
    <div className="visit-risk-page">
      {error && (
        <div style={{marginBottom: 16}}>
          <Notice tone="danger">{error}</Notice>
        </div>
      )}

      <Panel
        title="مراجعة مخاطر الزيارات والمهام الميدانية"
        subtitle="تقييم المخاطر وتحديد اشتراطات المرافقة للكوادر التمريضية قبل بدء الزيارة"
        action={
          <button className="action-btn" onClick={() => void load()} title="تحديث قائمة الزيارات">
            <RefreshCw size={15} />
            <span>تحديث</span>
          </button>
        }
      >
        <div className="form one">
          <label>
            اختر الزيارة المراد تقييم مستوى أمانها
            <select
              value={selected?.id ?? ''}
              onChange={e => setRequestId(e.currentTarget.value)}
              style={{fontSize: 14, fontWeight: 500}}
            >
              <option value="">-- اضغط لاختيار زيارة من قائمة المراجعة --</option>
              {queue?.requests.map(row => (
                <option key={row.id} value={row.id}>
                  {row.title_ar} · {row.appointment_at ? clock.format(new Date(row.appointment_at)) : 'طلب فوري'} (معرف: {row.id.slice(0, 8)})
                </option>
              ))}
            </select>
          </label>
        </div>

        {selected && (
          <div style={{marginTop: 20}}>
            {selected.decision && selected.effective_until && (
              <div style={{marginBottom: 16}}>
                <Notice tone={selected.decision === 'CLEAR' ? 'success' : 'warn'}>
                  آخر تقييم مسجل للزيارة: <strong>{decisions[selected.decision]}</strong> — سارٍ حتى {clock.format(new Date(selected.effective_until))}
                </Notice>
              </div>
            )}

            <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 20}}>
              {/* Form 1: Risk Assessment Decision */}
              <div style={{background: 'var(--canvas)', padding: 18, borderRadius: 12, border: '1px solid var(--border)'}}>
                <h3 style={{fontSize: 15, color: 'var(--navy)', marginBottom: 14}}>تسجيل قرار تقييم المخاطر</h3>
                <form onSubmit={event => void submit(event, 'risk')} className="form one">
                  <label>
                    القرار الأمني
                    <select value={decision} onChange={e => setDecision(e.currentTarget.value as Decision)}>
                      {Object.entries(decisions).map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label>
                    الأساس والسبب الموثق
                    <select value={basis} onChange={e => setBasis(e.currentTarget.value as Basis)}>
                      {Object.entries(bases).map(([key, label]) => (
                        <option key={key} value={key}>
                          {label}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label>
                    مرجع التوثيق والملاحظة
                    <input
                      maxLength={120}
                      required
                      placeholder="رقم البلاغ أو مرجع المراجعة"
                      value={reference}
                      onChange={e => setReference(e.currentTarget.value)}
                    />
                  </label>

                  <label>
                    صلاحية القرار (بالساعات)
                    <input
                      type="number"
                      min="1"
                      max="168"
                      required
                      value={hours}
                      onChange={e => setHours(e.currentTarget.valueAsNumber)}
                    />
                  </label>

                  <div className="actions" style={{marginTop: 10}}>
                    <button className="pill on" disabled={busy || !reference.trim()} type="submit">
                      اعتماد وتثبيت القرار
                    </button>
                  </div>
                </form>
              </div>

              {/* Form 2: Professional Companion Nomination */}
              <div style={{background: 'var(--canvas)', padding: 18, borderRadius: 12, border: '1px solid var(--border)'}}>
                <h3 style={{fontSize: 15, color: 'var(--navy)', marginBottom: 14}}>تعيين مرافق مهني معتمد للزيارة</h3>
                <form onSubmit={event => void submit(event, 'companion')} className="form one">
                  <label>
                    الممرض المكلف الأساسي
                    <select required value={nurseId} onChange={e => setNurseId(e.currentTarget.value)}>
                      <option value="">اختر الممرض الأساسي</option>
                      {queue?.nurses.map(row => (
                        <option key={row.id} value={row.id}>
                          {row.display_name ?? row.id}
                        </option>
                      ))}
                    </select>
                  </label>

                  <label>
                    المرافق التمريضي / الأمني المصاحب
                    <select required value={companionId} onChange={e => setCompanionId(e.currentTarget.value)}>
                      <option value="">اختر المرافق المصاحب</option>
                      {queue?.nurses.map(row => (
                        <option key={row.id} value={row.id}>
                          {row.display_name ?? row.id}
                        </option>
                      ))}
                    </select>
                  </label>

                  <div className="actions" style={{marginTop: 20}}>
                    <button
                      className="pill on"
                      disabled={busy || !nurseId || !companionId || nurseId === companionId}
                      type="submit"
                    >
                      تأكيد وإسناد المرافقة
                    </button>
                  </div>
                </form>
              </div>
            </div>
          </div>
        )}
      </Panel>
    </div>
  );
}
