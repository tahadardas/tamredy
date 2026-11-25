import {useEffect, useState} from 'react';
import {statusConfig, type Live} from './pages';
import {getJson, msgOf, sendJson} from './session';
import {Panel, Table} from './ui';
import {Modal, useBusy} from './widgets';
import {RequestVisitRecord} from './request_visit_record';

type Visit = {
  id: string; status: string; appointment_at: string; address_text: string;
  beneficiary_name: string; service_title: string; assigned_nurse: string | null;
  arrived_nurse: string | null; arrived_at: string | null;
};
type Plan = {
  id: string; status: string; beneficiary_name: string; service_title: string;
  frequency_type: string; completed: number; total_visits_planned: number | null; next_visit: string | null;
};
type Page<T> = {items: T[]; hasMore: boolean};
const clock = new Intl.DateTimeFormat('ar-SY', {dateStyle: 'medium', timeStyle: 'short', timeZone: 'Asia/Damascus'});
const date = (value: string | null) => value ? clock.format(new Date(value)) : '—';
const frequencies: Record<string,string> = {DAILY:'يومي',EVERY_OTHER_DAY:'كل يومين',THREE_TIMES_A_WEEK:'ثلاث مرات أسبوعيًا',SPECIFIC_DAYS:'أيام محددة'};
const planStatuses: Record<string,string> = {ACTIVE:'نشطة',PAUSED:'متوقفة مؤقتًا',COMPLETED:'مكتملة',CANCELLED:'ملغاة'};
const visitStatuses: Record<string,string> = {
  SCHEDULED:'مجدولة',EXPIRED:'انتهت المهلة',AWAITING_RECOVERY_CHOICE:'بانتظار قرار المريض',OPEN_FOR_PROPOSALS:'مفتوحة للعروض',
};
const removable = ['SCHEDULED','COMPLETED','CANCELLED','UNFULFILLED','EXPIRED','ESCALATED'];

export function AppointmentsSchedule({live}: {live: Live}) {
  const [tab, setTab] = useState<'visits' | 'removed' | 'care-plans'>('visits');
  const [page, setPage] = useState(1);
  const [revision, refresh] = useState(0);
  const [visits, setVisits] = useState<Page<Visit>>();
  const [plans, setPlans] = useState<Page<Plan>>();
  const [error, setError] = useState('');
  const [details, setDetails] = useState<Visit>();
  const [removing, setRemoving] = useState<Visit>();
  const {busy, err, run, setErr} = useBusy();

  useEffect(() => {
    let current = true;
    setError('');
    setVisits(undefined);
    setPlans(undefined);
    const path = tab === 'care-plans' ? 'care-plans' : 'visits';
    getJson(`/v1/admin/schedule/${path}?page=${page}&removed=${tab === 'removed'}`).then(result => {
      if (!current) return;
      if (tab === 'care-plans') setPlans(result);
      else setVisits(result);
    }).catch(e => {if (current) setError(msgOf(e));});
    return () => {current = false;};
  }, [tab,page,revision,live.token]);

  const result = tab === 'care-plans' ? plans : visits;
  return <Panel title="الزيارات المجدولة وخطط الرعاية">
    <div className="toolbar">
      <button className={`pill ${tab === 'visits' ? 'on' : ''}`} onClick={() => {setTab('visits');setPage(1);}}>الزيارات المجدولة</button>
      <button className={`pill ${tab === 'removed' ? 'on' : ''}`} onClick={() => {setTab('removed');setPage(1);}}>الزيارات المؤرشفة</button>
      <button className={`pill ${tab === 'care-plans' ? 'on' : ''}`} onClick={() => {setTab('care-plans');setPage(1);}}>خطط الرعاية</button>
      <button className="pill" onClick={() => refresh(n => n + 1)}>تحديث القائمة</button>
    </div>
    {error && <p className="err" role="alert">{error}</p>}
    {!error && !result && <p role="status">جارٍ التحميل…</p>}
    {result?.items.length === 0 && <p>لا توجد سجلات في هذه الصفحة.</p>}
    {!!visits?.items.length && <Table head={['المستفيد','الخدمة','موعد الزيارة بتوقيت دمشق','العنوان','الحالة','الممرض المكلّف حاليًا','الوصول المسجّل','الإجراءات']}
      rows={visits.items.map(v => [
        v.beneficiary_name, v.service_title, date(v.appointment_at), v.address_text,
        visitStatuses[v.status] ?? statusConfig[v.status]?.label ?? v.status, v.assigned_nurse ?? '—',
        v.arrived_at ? `${v.arrived_nurse ?? 'الاسم غير مسجل'} · ${date(v.arrived_at)}` : 'لم يُسجّل وصول',
        <span className="acts" key={v.id}>
          <button className="pill" onClick={() => setDetails(v)}>تتبّع الزيارة</button>
          {tab === 'visits' && removable.includes(v.status) && <button className="pill danger" onClick={() => {setErr('');setRemoving(v);}}>{v.status === 'SCHEDULED' ? 'إلغاء وأرشفة' : 'أرشفة'}</button>}
        </span>,
      ])}/>}
    {!!plans?.items.length && <Table head={['المستفيد','الخدمة','التكرار','الزيارات المكتملة','الزيارة القادمة','الحالة']}
      rows={plans.items.map(p => [p.beneficiary_name,p.service_title,frequencies[p.frequency_type] ?? p.frequency_type,
        p.total_visits_planned == null ? p.completed : `${p.completed} / ${p.total_visits_planned}`,
        date(p.next_visit),planStatuses[p.status] ?? p.status])}/>}
    <div className="actions">
      <button className="pill" disabled={page === 1} onClick={() => setPage(n => n - 1)}>السابق</button>
      <button className="pill" disabled={!result?.hasMore} onClick={() => setPage(n => n + 1)}>التالي</button>
    </div>
    {details && <Modal title={`تتبّع زيارة ${details.beneficiary_name}`} onClose={() => setDetails(undefined)}>
      <RequestVisitRecord id={details.id}/>
    </Modal>}
    {removing && <Modal title={`أرشفة زيارة ${removing.beneficiary_name}`} onClose={() => {if (!busy) setRemoving(undefined);}}>
      <p>{removing.status === 'SCHEDULED' ? 'سيُلغى الموعد ويُخطر المريض.' : 'ستنتقل الزيارة إلى قائمة المؤرشفة.'} يبقى سجل الزيارة محفوظًا للمراجعة.</p>
      {err && <p className="err" role="alert">{err}</p>}
      <button className="pill danger" disabled={busy} onClick={() => void run(async () => {
        await sendJson('DELETE', `/v1/admin/schedule/visits/${removing.id}`);
        setRemoving(undefined);
        refresh(n => n + 1);
      })}>تأكيد</button>
    </Modal>}
  </Panel>;
}
