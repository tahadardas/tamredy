import {useCallback, useEffect, useRef, useState} from 'react';
import {getJson, msgOf, sendJson} from './session';
import {SafetyShifts, ShiftCoverage, type ShiftCoverageProps} from './safety_shifts';

type State = 'RECEIVED' | 'ACKNOWLEDGED' | 'ESCALATED' | 'RESOLVED';
type Command = 'acknowledge' | 'escalate' | 'resolve';
const stateLabel: Record<State, string> = {
  RECEIVED: 'بانتظار الاستلام',
  ACKNOWLEDGED: 'استلمه موظف',
  ESCALATED: 'مصعّد للمشرف',
  RESOLVED: 'أُغلق',
};
const kindLabel: Record<string, string> = {
  SOS: 'استغاثة',
  CHECKIN_MISSED: 'تحقق فائت',
  CHECKIN_HELP: 'طلب مساعدة',
  SAFE_EXIT_REQUESTED: 'طلب خروج آمن',
};
const commandLabel: Record<Command, string> = {
  acknowledge: 'استلام البلاغ',
  escalate: 'التصعيد إلى المشرف',
  resolve: 'إغلاق البلاغ',
};
const routingLabel: Record<string, string> = {
  PRIMARY: 'أُحيل إلى المناوب الأساسي',
  BACKUP: 'أُحيل إلى المناوب الاحتياطي',
  SUPERVISOR: 'أُحيل إلى المشرف المناوب',
  UNCOVERED: 'لا توجد جهة مناوبة متاحة',
};
type CaseRow = {id: string; routing_stage?: string; next_route_at?: string; state: State; version: number; kind: string; opened_at: string; assigned_user_id?: string};
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
  counts: {received: number; acknowledged: number; escalated: number; open_sos: number; missed_checkins: number; last_update: string | null};
};
type PendingAction = {id: string; version: number; command: Command; note: string; key: string};

function date(value?: string | null) {
  return value ? new Intl.DateTimeFormat('ar-SY', {
    dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Damascus',
  }).format(new Date(value)) : 'غير متاح';
}

export function SafetyOperations() {
  const [overview, setOverview] = useState<Overview>();
  const [cases, setCases] = useState<CaseRow[]>([]);
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
      const next = await getJson('/v1/admin/safety/dashboard') as Overview;
      const rows = await getJson('/v1/admin/safety/events') as CaseRow[];
      setOverview(next);
      setCases(rows);
      setUpdated(new Date().toISOString());
      setError('');
    } catch (error) {
      setError(msgOf(error));
      setOverview(undefined);
      setCases([]);
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

  async function open(row: CaseRow, mayRead = overview?.canResolve) {
    const sequence = ++detailSequence.current;
    setSelected(row);
    setDetail(undefined);
    setDetailError('');
    setNote('');
    setDetailLoading(false);
    if (!mayRead && !row.assigned_user_id) return;
    setDetailLoading(true);
    try {
      const result = await getJson(`/v1/admin/safety/events/${row.id}`) as CaseDetail;
      if (sequence === detailSequence.current) setDetail(result);
    } catch (error) {
      if (sequence === detailSequence.current) setDetailError(msgOf(error));
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
    if (!action || action.id !== row.id || action.version !== row.version || action.command !== command || action.note !== text) {
      action = {id: row.id, version: row.version, command, note: text, key: crypto.randomUUID()};
      pending.current = action;
    }
    setBusy(true);
    setDetailError('');
    try {
      const changed = await sendJson('POST', `/v1/admin/safety/events/${row.id}/${command}`, {
        expectedVersion: action.version, clientActionId: action.key, ...(text ? {note: text} : {}),
      }) as Pick<CaseRow, 'state' | 'version'>;
      pending.current = null;
      await open({...row, ...changed}, true);
      await load();
    } catch (error) {
      setDetailError(msgOf(error));
      await load();
    } finally {
      setBusy(false);
    }
  }

  if (!overview) return <section className="card">
    {error ? <p role="alert">{error}</p> : <p>جارٍ تحميل لوحة السلامة…</p>}
    <button className="pill" onClick={() => void load()}>إعادة التحميل</button>
  </section>;

  const counts = overview.counts;
  const shown = cases.filter(row => filter === 'OPEN' ? row.state !== 'RESOLVED' : row.state === filter);
  const current = detail ?? selected;
  return <section aria-label="مركز عمليات السلامة">
    <div className="card">
      <ShiftCoverage coverage={overview.coverage} shifts={overview.shifts} />
      <p>بانتظار الاستلام {counts.received} · مستلمة {counts.acknowledged} · مصعّدة {counts.escalated}</p>
      <p>استغاثات مفتوحة {counts.open_sos} · تنبيهات تحقق فائتة {counts.missed_checkins}</p>
      <p>آخر تغيير في البلاغات {date(counts.last_update)} · آخر تحديث للقائمة {date(updated)}</p>
      <button className="pill" disabled={busy} onClick={() => void load()}>تحديث قائمة البلاغات</button>
    </div>
    <SafetyShifts onPresence={load} />
    <label>حالة البلاغ <select value={filter} onChange={event => setFilter(event.currentTarget.value as State | 'OPEN')}>
      <option value="OPEN">البلاغات المفتوحة</option>
      {Object.entries(stateLabel).map(([key,label]) => <option key={key} value={key}>{label}</option>)}
    </select></label>
    {shown.length ? <ul>{shown.map(row => <li key={row.id}>
      <button className="pill" disabled={busy} onClick={() => void open(row)}>
        {kindLabel[row.kind] ?? row.kind} · {stateLabel[row.state]} · {date(row.opened_at)}
      </button>
    </li>)}</ul> : <p>لا توجد بلاغات مطابقة في القائمة الحالية.</p>}
    {current && <div className="card" aria-label="تفاصيل البلاغ">
      <h2>{kindLabel[current.kind] ?? current.kind}</h2>
      <p>{stateLabel[current.state]}</p>
      {current.state === 'RECEIVED' && current.routing_stage && routingLabel[current.routing_stage] &&
        <p>{routingLabel[current.routing_stage]}{current.assigned_user_id && current.next_route_at ? ` · مهلة الاستلام ${date(current.next_route_at)}` : ''}</p>}
      {detailLoading && <p>جارٍ تحميل تفاصيل البلاغ…</p>}
      {detailError && <p role="alert">{detailError}</p>}
      {detail && <>
        {detail.silent && <p><strong>استغاثة صامتة.</strong> التزم بقناة تواصل آمنة قبل الاتصال بالمبلّغ.</p>}
        {detail.reporter_name && <p>المبلّغ {detail.reporter_name}</p>}
        {detail.assignment_id && <p>الإسناد <bdi>{detail.assignment_id}</bdi></p>}
        {detail.triggered_at && <p>وقت طلب الاستغاثة {date(detail.triggered_at)}</p>}
        {detail.received_at && <p>وقت تسجيلها على الخادم {date(detail.received_at)}</p>}
        {detail.routes.length > 0 && <ul>{detail.routes.map((route,index) => <li key={index}>
          {routingLabel[route.route_stage]} · {date(route.routed_at)}
        </li>)}</ul>}
        {detail.actions.length > 0 && <ul>{detail.actions.map(item => <li key={item.resulting_version}>
          {stateLabel[item.action]} · {date(item.created_at)} {item.note && <p>{item.note}</p>}
        </li>)}</ul>}
      </>}
      {current.state === 'RECEIVED' && (overview.canResolve || !overview.routingEnabled || !!current.assigned_user_id) &&
        <button className="pill" disabled={busy} onClick={() => void act('acknowledge')}>{commandLabel.acknowledge}</button>}
      {detail && (detail.state === 'ACKNOWLEDGED' || (overview.canResolve && detail.state === 'ESCALATED')) && <>
        <label>توثيق الإجراء <textarea maxLength={500} value={note} disabled={busy} onChange={event => setNote(event.currentTarget.value)} /></label>
        {detail.state === 'ACKNOWLEDGED' &&
          <button className="pill" disabled={busy || !note.trim()} onClick={() => void act('escalate')}>{commandLabel.escalate}</button>}
        {overview.canResolve &&
          <button className="pill" disabled={busy || !note.trim()} onClick={() => void act('resolve')}>{commandLabel.resolve}</button>}
      </>}
    </div>}
  </section>;
}
