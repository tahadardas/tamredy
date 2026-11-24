import {useCallback, useEffect, useRef, useState} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {SafetyShifts, ShiftCoverage, type ShiftCoverageProps} from './safety_shifts';
import {Chip, Notice, Panel, Stat, Table} from './ui';
import {Modal} from './widgets';
import {AlertOctagon, CheckCircle2, Clock, Filter, PhoneIncoming, RefreshCw, ShieldAlert, UserCheck, ArrowRightLeft} from 'lucide-react';

type State = 'RECEIVED' | 'ACKNOWLEDGED' | 'ESCALATED' | 'RESOLVED';
type Command = 'acknowledge' | 'escalate' | 'resolve';

const stateLabel: Record<State, string> = {
  RECEIVED: 'بانتظار الاستلام',
  ACKNOWLEDGED: 'استلمه موظف',
  ESCALATED: 'مصعّد للمشرف',
  RESOLVED: 'أُغلق البلاغ',
};

const kindLabel: Record<string, string> = {
  SOS: 'استغاثة طارئة',
  CHECKIN_MISSED: 'تحقق فائت',
  CHECKIN_HELP: 'طلب مساعدة ميدانية',
  SAFE_EXIT_REQUESTED: 'طلب خروج آمن',
};

const commandLabel: Record<Command, string> = {
  acknowledge: 'استلام ومتابعة البلاغ',
  escalate: 'التصعيد إلى المشرف العام',
  resolve: 'إغلاق البلاغ وحله نهائياً',
};

const routingLabel: Record<string, string> = {
  PRIMARY: 'أُحيل إلى المناوب الأساسي',
  BACKUP: 'أُحيل إلى المناوب الاحتياطي',
  SUPERVISOR: 'أُحيل إلى المشرف المناوب',
  UNCOVERED: 'لا توجد جهة مناوبة متاحة',
};

type CaseRow = {
  id: string;
  routing_stage?: string;
  next_route_at?: string;
  state: State;
  version: number;
  kind: string;
  opened_at: string;
  assigned_user_id?: string;
};

type CaseDetail = CaseRow & {
  reporter_name: string | null;
  assignment_id: string | null;
  silent: boolean | null;
  triggered_at?: string | null;
  received_at?: string | null;
  routes: {route_stage: string; routed_at: string; acknowledge_by: string}[];
  actions: {actor_user_id: string; action: State; note: string | null; resulting_version: number; created_at: string}[];
};

type Overview = {
  canResolve: boolean;
  routingEnabled: boolean;
  coverage: ShiftCoverageProps['coverage'];
  shifts: ShiftCoverageProps['shifts'];
  counts: {
    received: number;
    acknowledged: number;
    escalated: number;
    open_sos: number;
    missed_checkins: number;
    last_update: string | null;
  };
};

type Handover = {id: string; case_id: string; expires_at: string};
type Candidate = {user_id: string; shift_id: string; display_name: string | null; governorate_name: string | null};
type PendingAction = {id: string; version: number; command: Command; note: string; key: string};

function date(value?: string | null) {
  return value
    ? new Intl.DateTimeFormat('ar-SY', {
        dateStyle: 'medium',
        timeStyle: 'short',
        timeZone: 'Asia/Damascus',
      }).format(new Date(value))
    : 'غير متاح';
}

export function SafetyOperations() {
  const [overview, setOverview] = useState<Overview>();
  const [cases, setCases] = useState<CaseRow[]>([]);
  const [handovers, setHandovers] = useState<Handover[]>([]);
  const [candidates, setCandidates] = useState<Candidate[]>([]);
  const [recipient, setRecipient] = useState('');
  const [filter, setFilter] = useState<State | 'OPEN'>('OPEN');
  const [error, setError] = useState('');
  const [updated, setUpdated] = useState<string>();
  const [detail, setDetail] = useState<CaseDetail>();
  const [detailError, setDetailError] = useState('');
  const [detailLoading, setDetailLoading] = useState(false);
  const [selected, setSelected] = useState<CaseRow>();
  const [busy, setBusy] = useState(false);
  const [note, setNote] = useState('');
  const pending = useRef<PendingAction | null>(null);
  const reading = useRef(false);
  const detailSequence = useRef(0);

  const load = useCallback(async () => {
    if (reading.current) return;
    reading.current = true;
    try {
      const next = (await getJson('/v1/admin/safety/dashboard')) as Overview;
      const [rows, offers] = await Promise.all([
        getJson('/v1/admin/safety/events') as Promise<CaseRow[]>,
        getJson('/v1/admin/safety/handovers') as Promise<Handover[]>,
      ]);
      setHandovers(offers);
      setOverview(next);
      setCases(rows);
      setUpdated(new Date().toISOString());
      setError('');
    } catch (err) {
      setError(msgOf(err));
      setOverview(undefined);
      setCases([]);
      setHandovers([]);
      setDetail(undefined);
      setSelected(undefined);
      detailSequence.current++;
      setDetailLoading(false);
    } finally {
      reading.current = false;
    }
  }, []);

  useEffect(() => {
    void load();
    const interval = window.setInterval(() => {
      if (document.visibilityState === 'visible') void load();
    }, 20000);
    return () => {
      window.clearInterval(interval);
      detailSequence.current++;
    };
  }, [load]);

  useEffect(() => {
    if (selected && !cases.some(row => row.id === selected.id)) {
      detailSequence.current++;
      setSelected(undefined);
      setDetail(undefined);
      setCandidates([]);
      setDetailLoading(false);
    }
  }, [cases, selected]);

  async function open(row: CaseRow, mayRead = overview?.canResolve ?? true) {
    const sequence = ++detailSequence.current;
    setSelected(row);
    setDetail(undefined);
    setCandidates([]);
    setRecipient('');
    setDetailError('');
    setNote('');
    setDetailLoading(false);
    if (!mayRead && !row.assigned_user_id) return;
    setDetailLoading(true);
    try {
      const result = (await getJson(`/v1/admin/safety/events/${row.id}`)) as CaseDetail;
      if (sequence === detailSequence.current) setDetail(result);
    } catch (err) {
      if (sequence === detailSequence.current) setDetailError(msgOf(err));
    } finally {
      if (sequence === detailSequence.current) setDetailLoading(false);
    }
  }

  async function act(command: Command) {
    if (busy || !selected) return;
    const row = detail ?? selected;
    const text = command === 'acknowledge' ? '' : note.trim();
    if (command !== 'acknowledge' && !text) return;
    let action = pending.current;
    if (
      !action ||
      action.id !== row.id ||
      action.version !== row.version ||
      action.command !== command ||
      action.note !== text
    ) {
      action = {id: row.id, version: row.version, command, note: text, key: crypto.randomUUID()};
      pending.current = action;
    }
    setBusy(true);
    setDetailError('');
    try {
      const changed = (await sendJson('POST', `/v1/admin/safety/events/${row.id}/${command}`, {
        expectedVersion: action.version,
        clientActionId: action.key,
        ...(text ? {note: text} : {}),
      })) as Pick<CaseRow, 'state' | 'version'>;
      pending.current = null;
      await open({...row, ...changed}, true);
      await load();
    } catch (err) {
      setDetailError(msgOf(err));
      await load();
    } finally {
      setBusy(false);
    }
  }

  async function handoverCommand(work: () => Promise<void>) {
    if (busy) return;
    setBusy(true);
    setDetailError('');
    try {
      await work();
    } catch (err) {
      setDetailError(msgOf(err));
    } finally {
      setBusy(false);
    }
  }

  if (!overview) {
    return (
      <Panel title="مركز عمليات السلامة الميدانية" subtitle="تحميل غرفة العمليات...">
        {error ? (
          <div style={{marginBottom: 16}}>
            <Notice tone="danger">{error}</Notice>
            <div style={{marginTop: 12}}>
              <button className="pill on" onClick={() => void load()}>
                إعادة التحميل
              </button>
            </div>
          </div>
        ) : (
          <p>جارٍ تحميل بيانات السلامة...</p>
        )}
      </Panel>
    );
  }

  const counts = overview.counts;
  const shown = cases.filter(row => (filter === 'OPEN' ? row.state !== 'RESOLVED' : row.state === filter));
  const current = detail ?? selected;

  return (
    <div className="safety-operations-page">
      {/* Top Telemetry Metric Cards */}
      <div className="stats" style={{marginBottom: 20}}>
        <Stat
          icon="alert"
          label="استغاثات طارئة مفتوحة"
          value={counts.open_sos}
          sub="بلاغات SOS نشطة تتطلب استجابة فورية"
          trend={counts.open_sos > 0 ? {label: 'حرجة', up: true} : undefined}
        />
        <Stat
          icon="clock"
          label="بانتظار الاستلام"
          value={counts.received}
          sub="بلاغات جديدة في طابور التوزيع"
        />
        <Stat
          icon="pulse"
          label="قيد المتابعة والتصعيد"
          value={counts.acknowledged + counts.escalated}
          sub={`مستلمة: ${counts.acknowledged} | مصعدة: ${counts.escalated}`}
        />
        <Stat
          icon="shield"
          label="تنبيهات تحقق فائتة"
          value={counts.missed_checkins}
          sub="حالات عدم استجابة في الوقت المحدد"
        />
      </div>

      {/* Coverage Status */}
      <ShiftCoverage coverage={overview.coverage} shifts={overview.shifts} />

      {/* Handovers Waiting Alert */}
      {handovers.length > 0 && (
        <div style={{marginBottom: 20}}>
          <Notice tone="warn">
            <strong>توجد بلاغات معروضة عليك للتسليم:</strong>
            <div style={{display: 'flex', gap: 10, marginTop: 8, flexWrap: 'wrap'}}>
              {handovers.map(offer => (
                <button
                  className="pill on"
                  key={offer.id}
                  disabled={busy}
                  onClick={() =>
                    void handoverCommand(async () => {
                      await sendJson('POST', `/v1/admin/safety/handovers/${offer.id}/accept`);
                      await load();
                    })
                  }
                >
                  قبول مسؤولية البلاغ #{offer.case_id.slice(0, 8)} (صالح حتى {date(offer.expires_at)})
                </button>
              ))}
            </div>
          </Notice>
        </div>
      )}

      {/* Safety Cases Table Panel */}
      <Panel
        title="غرفة بلاغات وحوادث السلامة"
        subtitle={`آخر تحديث: ${date(updated)}`}
        action={
          <div style={{display: 'flex', gap: 10, alignItems: 'center'}}>
            <select
              value={filter}
              onChange={event => setFilter(event.currentTarget.value as State | 'OPEN')}
              style={{fontSize: 13, padding: '6px 12px'}}
            >
              <option value="OPEN">كافة البلاغات المفتوحة</option>
              {Object.entries(stateLabel).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>
            <button className="action-btn" onClick={() => void load()} title="تحديث القائمة">
              <RefreshCw size={15} />
              <span>تحديث</span>
            </button>
          </div>
        }
      >
        {shown.length === 0 ? (
          <div className="empty-hint">لا توجد بلاغات تطابق التصفية الحالية. جميع الأوضاع الميدانية مستقرة.</div>
        ) : (
          <Table
            head={['نوع البلاغ', 'حالة البلاغ', 'مرحلة التوجيه', 'وقت فتح البلاغ', 'الإجراءات']}
            rows={shown.map(row => {
              const tone =
                row.state === 'RECEIVED'
                  ? 'danger'
                  : row.state === 'ESCALATED'
                  ? 'purple'
                  : row.state === 'ACKNOWLEDGED'
                  ? 'warn'
                  : 'success';

              return [
                <div key="kind" style={{display: 'flex', alignItems: 'center', gap: 8}}>
                  <strong style={{color: 'var(--navy)', fontSize: 14}}>{kindLabel[row.kind] ?? row.kind}</strong>
                  <small style={{color: 'var(--sub)'}}>#{row.id.slice(0, 8)}</small>
                </div>,
                <Chip key="state" tone={tone}>
                  {stateLabel[row.state]}
                </Chip>,
                row.routing_stage ? routingLabel[row.routing_stage] ?? row.routing_stage : 'بانتظار التوجيه',
                date(row.opened_at),
                <button key="btn" className="pill on" disabled={busy} onClick={() => void open(row)}>
                  معاينة ومتابعة البلاغ
                </button>,
              ];
            })}
          />
        )}
      </Panel>

      {/* Shift Roster Sub-component */}
      <SafetyShifts onPresence={load} />

      {/* Case Details Modal (Portal-Rooted) */}
      {current && (
        <Modal title={`متابعة البلاغ: ${kindLabel[current.kind] ?? current.kind}`} onClose={() => setSelected(undefined)}>
          {detailLoading && <p style={{color: 'var(--sub)'}}>جارٍ تحميل بيانات وسجل البلاغ...</p>}
          {detailError && (
            <div style={{marginBottom: 14}}>
              <Notice tone="danger">{detailError}</Notice>
            </div>
          )}

          {detail && (
            <div style={{display: 'flex', flexDirection: 'column', gap: 16}}>
              {detail.silent && (
                <Notice tone="danger">
                  <strong>تحذير أمني: استغاثة صامتة.</strong> يرجى الالتزام بقناة تواصل آمنة والتأكد من أمان الكادر قبل الاتصال المباشر.
                </Notice>
              )}

              <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, background: 'var(--canvas)', padding: 14, borderRadius: 10}}>
                <div><strong>المبلّغ:</strong> {detail.reporter_name ?? 'غير مسجل'}</div>
                <div><strong>معرف الإسناد:</strong> <bdi>{detail.assignment_id ?? 'بدون إسناد'}</bdi></div>
                <div><strong>وقت إطلاق الاستغاثة:</strong> {date(detail.triggered_at)}</div>
                <div><strong>وقت الاستلام في السيرفر:</strong> {date(detail.received_at)}</div>
                <div><strong>الحالة الحالية:</strong> <Chip tone={detail.state === 'RECEIVED' ? 'danger' : 'warn'}>{stateLabel[detail.state]}</Chip></div>
                <div><strong>الإصدار:</strong> {detail.version}</div>
              </div>

              {detail.actions.length > 0 && (
                <div>
                  <h4 style={{fontSize: 13, marginBottom: 8, color: 'var(--navy)'}}>سجل الإجراءات المتخذة:</h4>
                  <div style={{display: 'flex', flexDirection: 'column', gap: 6}}>
                    {detail.actions.map(actItem => (
                      <div key={actItem.resulting_version} style={{background: '#ffffff', border: '1px solid var(--border)', padding: '8px 12px', borderRadius: 8, fontSize: 12}}>
                        <div style={{display: 'flex', justifyContent: 'space-between', marginBottom: 4}}>
                          <strong>{stateLabel[actItem.action]}</strong>
                          <span style={{color: 'var(--sub)'}}>{date(actItem.created_at)}</span>
                        </div>
                        {actItem.note && <p style={{margin: 0, color: 'var(--text)'}}>{actItem.note}</p>}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {/* Action Area */}
              <div style={{borderTop: '1px solid var(--border)', paddingTop: 16}}>
                {current.state === 'RECEIVED' && (
                  <button className="pill on" disabled={busy} onClick={() => void act('acknowledge')}>
                    {commandLabel.acknowledge}
                  </button>
                )}

                {['ACKNOWLEDGED', 'ESCALATED'].includes(detail.state) && (
                  <div style={{display: 'flex', flexDirection: 'column', gap: 12}}>
                    <label className="form one">
                      توثيق الملاحظات والإجراءات الطبية / الأمنية
                      <textarea
                        rows={3}
                        maxLength={500}
                        placeholder="سجّل تقريرك أو سبب التصعيد أو الحل..."
                        value={note}
                        disabled={busy}
                        onChange={e => setNote(e.currentTarget.value)}
                      />
                    </label>

                    <div className="actions">
                      {detail.state === 'ACKNOWLEDGED' && (
                        <button className="pill" disabled={busy || !note.trim()} onClick={() => void act('escalate')}>
                          {commandLabel.escalate}
                        </button>
                      )}
                      <button className="pill on" disabled={busy || !note.trim()} onClick={() => void act('resolve')}>
                        {commandLabel.resolve}
                      </button>
                      <button
                        className="pill"
                        disabled={busy}
                        onClick={() =>
                          void handoverCommand(async () => {
                            const rows = (await getJson(`/v1/admin/safety/events/${detail.id}/handover-candidates`)) as Candidate[];
                            setCandidates(rows);
                            setRecipient('');
                            if (!rows.length) setDetailError('لا يوجد مناوب بديل حاضر للتسليم حالياً.');
                          })
                        }
                      >
                        <ArrowRightLeft size={14} style={{marginLeft: 4}} />
                        <span>تسليم البلاغ لمناوب آخر</span>
                      </button>
                    </div>

                    {candidates.length > 0 && (
                      <div style={{background: 'var(--canvas)', padding: 12, borderRadius: 8, display: 'flex', gap: 10, alignItems: 'center'}}>
                        <select
                          value={recipient}
                          onChange={e => setRecipient(e.currentTarget.value)}
                          style={{flex: 1}}
                        >
                          <option value="">-- اختر المناوب البديل --</option>
                          {candidates.map(cand => (
                            <option key={cand.shift_id + cand.user_id} value={cand.shift_id + cand.user_id}>
                              {cand.display_name ?? cand.user_id} ({cand.governorate_name ?? 'تغطية عامة'})
                            </option>
                          ))}
                        </select>
                        <button
                          className="pill on"
                          disabled={busy || !recipient}
                          onClick={() =>
                            void handoverCommand(async () => {
                              const target = candidates.find(c => c.shift_id + c.user_id === recipient);
                              if (!target) return;
                              await sendJson('POST', `/v1/admin/safety/events/${detail.id}/handover`, {
                                toUserId: target.user_id,
                                toShiftId: target.shift_id,
                                expectedVersion: detail.version,
                              });
                              setCandidates([]);
                              setDetailError('تم إرسال طلب التسليم، بانتظار قبول المناوب.');
                            })
                          }
                        >
                          تأكيد التسليم
                        </button>
                      </div>
                    )}
                  </div>
                )}
              </div>
            </div>
          )}
        </Modal>
      )}
    </div>
  );
}
