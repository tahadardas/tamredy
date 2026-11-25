import {useEffect, useState} from 'react';
import {getJson, msgOf} from './session';

type VisitRecord = {
  address_text: string; latitude: number | null; longitude: number | null;
  created_at: string; updated_at: string; accepted_at?: string; departed_at?: string;
  arrived_at?: string; service_started_at?: string; completed_at?: string; released_at?: string;
  visit_seconds: number | null; service_seconds: number | null;
  collected_amount: string | null; amount_due: string | null; currency_code: string;
  last_collected_at?: string; paid_at?: string; payment_status?: string;
  assignments?: {id: string; nurse_id: string; nurse_name: string | null; status: string; accepted_at: string; departed_at: string | null; arrived_at: string | null; started_at: string | null; completed_at: string | null; released_at: string | null}[];
  events: {id: string; event_type: string; occurred_at: string}[];
};

const clock = new Intl.DateTimeFormat('ar-SY', {dateStyle:'medium', timeStyle:'medium', timeZone:'Asia/Damascus'});
const eventLabels: Record<string,string> = {
  'request.created':'أُنشئ الطلب','request.assigned':'أُسند الطلب','request.cancelled':'أُلغي الطلب',
  'request.unfulfilled':'لم يُسند الطلب','request.schedule_released':'بدأ توزيع الزيارة المجدولة',
  'visit.depart':'انطلق الممرض','visit.arrive':'وصل الممرض','visit.start':'بدأت الخدمة',
  'visit.complete':'اكتملت الزيارة','visit.interrupted':'توقفت الزيارة',
  'payment.partial':'سُجّل تحصيل جزئي','payment.paid':'سُجّل اكتمال الدفع',
};

function duration(seconds: number | null) {
  if (seconds === null) return 'غير مسجلة';
  const hours = Math.floor(seconds/3600);
  return `${hours ? hours+' ساعة و' : ''}${Math.floor(seconds%3600/60)} دقيقة و${seconds%60} ثانية`;
}

export function RequestVisitRecord({id}: {id: string}) {
  const [data,setData] = useState<VisitRecord>();
  const [error,setError] = useState('');
  const [attempt,retry] = useState(0);
  useEffect(() => {
    let active = true;
    getJson(`/v1/admin/requests/${id}/visit-record`).then(result => {
      if (active) setData(result);
    }).catch(error => {if (active) setError(msgOf(error));});
    return () => {active = false;};
  }, [id,attempt]);
  if (error) return <div><p role="alert">{error}</p><button className="pill" onClick={() => {setError('');retry(attempt+1);}}>إعادة المحاولة</button></div>;
  if (!data) return <p role="status">جارٍ تحميل سجل الزيارة…</p>;
  const {latitude,longitude} = data;
  const map = latitude !== null && longitude !== null
    ? `https://www.openstreetmap.org/?mlat=${latitude}&mlon=${longitude}#map=17/${latitude}/${longitude}`
    : null;
  const stamps = [
    ['وقت الطلب',data.created_at],['وقت الإسناد',data.accepted_at],['الانطلاق',data.departed_at],
    ['الوصول',data.arrived_at],['بدء الخدمة',data.service_started_at],['نهاية الزيارة المسجلة',data.completed_at],
    ['تحرير الإسناد',data.released_at],['آخر تحصيل نقدي',data.last_collected_at],['اكتمال الدفع',data.paid_at],
    ['آخر تحديث للطلب',data.updated_at],
  ];
  return <section aria-label="سجل الزيارة">
    <h3>عنوان الزيارة المثبّت</h3>
    <p>{data.address_text || 'العنوان غير مسجل'}</p>
    {map && <>
      <p><bdi>{latitude}, {longitude}</bdi></p>
      <a className="pill" href={map} target="_blank" rel="noopener noreferrer">عرض الموقع على OpenStreetMap</a>
    </>}
    <h3>التوقيت بتوقيت دمشق</h3>
    <dl>
      {stamps.map(([label,value]) => value && <div key={label}><dt>{label}</dt><dd>{clock.format(new Date(value))}</dd></div>)}
      <dt>مدة البقاء المسجلة من الوصول إلى نهاية الزيارة</dt><dd>{duration(data.visit_seconds)}</dd>
      <dt>مدة تقديم الخدمة المسجلة</dt><dd>{duration(data.service_seconds)}</dd>
      <dt>المبلغ النقدي المحصّل والمسجّل</dt>
      <dd>{data.collected_amount === null ? 'لم يُسجّل تحصيل' : `${Number(data.collected_amount).toLocaleString('ar-SY')} ${data.currency_code}`}</dd>
      <dt>مبلغ الخدمة المستحق</dt>
      <dd>{data.amount_due === null || data.payment_status === 'NOT_DUE' ? 'لم تصدر فاتورة' : `${Number(data.amount_due).toLocaleString('ar-SY')} ${data.currency_code}`}</dd>
    </dl>
    {data.assignments && <><h3>سجل إسناد الممرضين</h3>
      {data.assignments.length === 0 ? <p>لم يُسند الطلب إلى ممرض.</p> : <ul>{data.assignments.map(a =>
        <li key={a.id}><strong>{a.nurse_name ?? a.nurse_id}</strong>
          <dl>{([
            ['الإسناد',a.accepted_at],['الانطلاق',a.departed_at],['الوصول',a.arrived_at],
            ['بدء الخدمة',a.started_at],['نهاية الزيارة',a.completed_at],['تحرير الإسناد',a.released_at],
          ] as const).map(([label,value]) => value && <div key={label}><dt>{label}</dt><dd>{clock.format(new Date(value))}</dd></div>)}</dl>
          {!a.arrived_at && <p>لم يُسجّل وصول لهذا الممرض.</p>}
        </li>)}</ul>}
    </>}
    {data.events.length > 0 && <><h3>الأحداث المسجلة</h3><ol>{data.events.map(event =>
      <li key={event.id}>{eventLabels[event.event_type] ?? event.event_type} · {clock.format(new Date(event.occurred_at))}</li>)}</ol></>}
  </section>;
}
