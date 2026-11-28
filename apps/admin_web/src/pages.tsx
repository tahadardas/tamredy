import {useState, useEffect} from 'react';
import {Chip, Notice, Panel, Row, Stat, Table, Icon, AeroHero, SidePanel, StatusBadge} from './ui';

import {RequestVisitRecord} from './request_visit_record';

export type Metrics = {
  available_nurses: number;
  busy_nurses?: number;
  searching_requests: number;
  en_route: number;
  in_service: number;
  completed_today?: number;
  cancelled_today?: number;
  escalated_requests?: number;
  grossBilledByCurrency?: Record<string,string>;
  commissionRevenueByCurrency?: Record<string,string>;
  discountExpenseByCurrency?: Record<string,string>;
  taxPayableByCurrency?: Record<string,string>;
  cashCollectedByCurrency?: Record<string,string>;
  outstandingReceivablesByCurrency?: Record<string,string>;
  nursePayablesByCurrency?: Record<string,string>;
  roundingAdjustmentsByCurrency?: Record<string,string>;
};
function byCurrency(amounts?: Record<string,string>) {
  return Object.entries(amounts ?? {}).map(([currency, amount]) => `${amount} ${currency}`).join(' / ') || '—';
}
export type RequestRow = {id: string; status: string; created_at: string; service_title?: string; beneficiary_name?: string};
export type Page<T> = {items: T[]; hasMore: boolean; nextCursor: string | null};

export type Live = {
  get: (p: string) => Promise<any>;
  token: string;
  apiBase: string;
  extra: Record<string, any>;
  metrics: Metrics | null;
  requests: RequestRow[];
  hasMore: boolean;
  loadMore: () => void;
  more: boolean;
  reload: () => Promise<void>;
  navigate?: (pageId: string) => void;
};

export const statusConfig: Record<string, {label: string; tone: 'default' | 'success' | 'warn' | 'danger' | 'info' | 'purple'}> = {
  OFFERING: {label: 'قيد البحث', tone: 'warn'},
  ASSIGNED: {label: 'تم الإسناد', tone: 'info'},
  EN_ROUTE: {label: 'في الطريق', tone: 'info'},
  ARRIVED: {label: 'وصل', tone: 'info'},
  IN_SERVICE: {label: 'قيد التنفيذ', tone: 'purple'},
  COMPLETED: {label: 'مكتملة', tone: 'success'},
  CANCELLED: {label: 'ملغاة', tone: 'danger'},
  UNFULFILLED: {label: 'غير مستجاب', tone: 'danger'},
  ESCALATED: {label: 'مرفوع للإشراف', tone: 'warn'},
};

export const statusAr: Record<string, string> = {
  OFFERING: 'قيد البحث',
  ASSIGNED: 'تم الإسناد',
  EN_ROUTE: 'في الطريق',
  ARRIVED: 'وصل',
  IN_SERVICE: 'قيد التنفيذ',
  COMPLETED: 'مكتملة',
  CANCELLED: 'ملغاة',
  UNFULFILLED: 'غير مستجاب',
  ESCALATED: 'مرفوع للإشراف',
};

export const ago = (iso: string) => {
  const s = Math.max(0, (Date.now() - new Date(iso).getTime()) / 1000);
  return s < 60 ? `منذ ${Math.round(s)} ثانية` : s < 3600 ? `منذ ${Math.round(s / 60)} دقيقة` : s < 86400 ? `منذ ${Math.round(s / 3600)} ساعة` : `منذ ${Math.round(s / 86400)} يوم`;
};

export const n = (v: number | string) => Number(v).toLocaleString('en-US');
const pad = (v: number) => String(v).padStart(2, '0');
const Empty = ({children = 'لا توجد بيانات بعد'}: {children?: string}) => <p className="hint empty-hint">{children}</p>;

const reqHead = ['الرقم', 'الخدمة', 'المستفيد', 'الحالة', 'الزمن'];
const reqRows = (live: Live) =>
  live.requests.map(r => {
    const st = statusConfig[r.status] ?? {label: r.status, tone: 'default'};
    return [
      <span key="id" className="mono-code">#{r.id.slice(0, 6)}</span>,
      <strong key="srv">{r.service_title ?? '—'}</strong>,
      r.beneficiary_name ?? '—',
      <Chip key="st" tone={st.tone}>{st.label}</Chip>,
      <span key="tm" className="text-muted">{ago(r.created_at)}</span>,
    ];
  });

export function Dashboard({live}: {live: Live}) {
  const m = live.metrics, x = live.extra;
  const weekly: {day: string; bookings: number}[] = x.extras?.weekly ?? [];
  const max = Math.max(1, ...weekly.map(w => w.bookings));
  const alerts: {icon: string; title: string; sub: string; chip: string; chipTone: 'warn' | 'danger' | 'info'}[] = [];
  const pending = x.pending?.items?.length ?? 0;
  if (pending) alerts.push({icon: 'doc', title: `${pending} ترخيص بانتظار الاعتماد`, sub: 'يتطلب مراجعة فورية في صفحة اعتماد التراخيص', chip: 'متابعة', chipTone: 'warn'});
  if (x.live?.unresponsive) alerts.push({icon: 'alert', title: `${x.live.unresponsive} ممرض غير مستجيب`, sub: 'حالتهم متاحة لكن دون نبض دوري حديث', chip: 'تحقق', chipTone: 'danger'});
  if (x.reviews?.safety_reports) alerts.push({icon: 'alert', title: `${x.reviews.safety_reports} بلاغ سلامة مفتوح`, sub: 'إشعار أمان عاجل من زيارة جارية أو سابقة', chip: 'أولوية قصوى', chipTone: 'danger'});
  if (x.reviews?.new_complaints) alerts.push({icon: 'star', title: `${x.reviews.new_complaints} شكوى جديدة`, sub: 'تقييمات ممرضين بانتظار المراجعة والاعتماد', chip: 'جديدة', chipTone: 'info'});
  if (m?.escalated_requests && m.escalated_requests > 0) {
    alerts.push({
      icon: 'alert',
      title: `${m.escalated_requests} طلب بحاجة لتدخل الإدارة عاجلاً`,
      sub: 'طلبات تم تصعيدها بسبب تعذر الإسناد أو بلاغات طارئة',
      chip: 'أولوية قصوى',
      chipTone: 'danger',
    });
  }

  return <>
    <AeroHero
      title="غرفة العمليات المركزية والتحكم الميداني"
      subtitle="مراقبة حية فورية للجاهزية الميدانية، موجات التوزيع الذكية، وسرعة استجابة الكوادر التمريضية في دمشق وريفها."
      badgeText="نظام المراقبة والتحكم الميداني الفوري"
      pills={[
        {label: `ممرضون متاحون: ${pad(m?.available_nurses ?? 0)}`, active: (m?.available_nurses ?? 0) > 0},
        {label: `زيارات جارية: ${pad(m?.in_service ?? 0)}`, active: (m?.in_service ?? 0) > 0},
        {label: `قيد البحث: ${pad(m?.searching_requests ?? 0)}`, active: (m?.searching_requests ?? 0) > 0},
        {label: 'محرك التوزيع الذكي نشط ✓'},
      ]}
    />

    <div className="section-title">
      <h3>المؤشرات التشغيلية الحية</h3>
      <small className="text-muted">مراقبة فورية للجاهزية الميدانية والطلبات النشطة</small>
    </div>
    <div className="stats">
      <Stat icon="users" label="ممرضون متاحون" value={pad(m?.available_nurses ?? 0)} sub="جاهزون لتلقي الطلبات"/>
      <Stat icon="pin" label="ممرضون مشغولون" value={pad(m?.busy_nurses ?? (m?.en_route ?? 0))} sub="في الطريق أو لدى المريض"/>
      <Stat icon="search" label="طلبات قيد البحث" value={pad(m?.searching_requests ?? 0)} sub="في موجات التوزيع الحالية"/>
      <Stat icon="pulse" label="زيارات جارية الآن" value={pad(m?.in_service ?? 0)} sub="قيد تقديم الرعاية الطبية"/>
    </div>

    <div className="section-title" style={{marginTop: '20px'}}>
      <h3>حصيلة اليوم والمؤشرات المالية</h3>
      <small className="text-muted">بيانات مثبتة من قاعدة البيانات</small>
    </div>
    <div className="stats">
      <Stat icon="check" label="زيارات مكتملة اليوم" value={pad(m?.completed_today ?? 0)} sub={`ملغاة: ${m?.cancelled_today ?? 0}`}/>
      <Stat icon="wallet" label="إجمالي الفوترة اليوم" value={byCurrency(m?.grossBilledByCurrency)} sub="قبل الخصومات"/>
      <Stat icon="cash" label="عمولة المنصة اليوم" value={byCurrency(m?.commissionRevenueByCurrency)} sub="صافي قيود العمولة"/>
      <Stat icon="alert" label="مستحقات المرضى" value={byCurrency(m?.outstandingReceivablesByCurrency)} sub="من دفتر الأستاذ"/>
      <Stat icon="cash" label="تحصيل نقدي اليوم" value={byCurrency(m?.cashCollectedByCurrency)}/>
      <Stat icon="wallet" label="مستحقات الممرضين" value={byCurrency(m?.nursePayablesByCurrency)}/>
      <Stat icon="wallet" label="مصروف الخصومات اليوم" value={byCurrency(m?.discountExpenseByCurrency)}/>
      <Stat icon="wallet" label="الضرائب المستحقة" value={byCurrency(m?.taxPayableByCurrency)}/>
      <Stat icon="cash" label="فروق التقريب اليوم" value={byCurrency(m?.roundingAdjustmentsByCurrency)}/>
    </div>

    <div className="grid2">
      <Panel title="أحدث الطلبات الواردة" subtitle="آخر العمليات على المنصة">
        {live.requests.length ? <Table head={reqHead} rows={reqRows(live).slice(0, 8)}/> : <Empty>لا توجد طلبات بعد</Empty>}
      </Panel>

      <Panel title="حجم الحجوزات اليومية (الأسبوع الحالي)" subtitle="معدل الزيارات لكل يوم">
        {weekly.length ? (
          <div className="weekly-chart">
            <div className="bars">
              {weekly.map(w => (
                <div key={w.day} className="bar-col">
                  <i title={`${w.day}: ${w.bookings}`} style={{height: `${Math.max(6, (w.bookings / max) * 100)}%`}}/>
                  <small>{w.day}</small>
                </div>
              ))}
            </div>
          </div>
        ) : <Empty>لا توجد بيانات حجوزات كافية للأسبوع</Empty>}
      </Panel>
    </div>

    <Panel title="تنبيهات تشغيلية تحتاج متابعة" subtitle="إجراءات معلقة من النظام والكوادر">
      {alerts.length ? (
        alerts.map(a => <Row key={a.title} icon={a.icon} title={a.title} sub={a.sub} chip={a.chip} chipTone={a.chipTone}/>)
      ) : (
        <Empty>لا توجد تنبيهات معلقة. كل شيء يسير بهدوء ✓</Empty>
      )}
    </Panel>
  </>;
}

export function LiveMap({live}: {live: Live}) {
  const x = live.extra.live;
  const cases: any[] = x?.cases ?? [];
  return <>
    <div className="stats">
      <Stat icon="users" label="المتاحون" value={x?.available ?? 0} sub="على اتصال بالخادم"/>
      <Stat icon="pin" label="في الطريق" value={pad(x?.en_route ?? 0)} sub="متجهون للمرضى"/>
      <Stat icon="pulse" label="داخل الزيارة" value={x?.in_visit ?? 0} sub="تقديم الرعاية"/>
      <Stat icon="alert" label="غير مستجاب" value={pad(x?.unresponsive ?? 0)} sub="انقطع الاتصال"/>
    </div>
    <Panel title="حالات المتابعة الميدانية الآن" subtitle="الزيارات النشطة وتفاصيلها الفورية">
      {cases.length ? (
        cases.map(c => {
          const st = statusConfig[c.status] ?? {label: c.status, tone: 'default'};
          return (
            <Row
              key={c.id}
              icon="pulse"
              title={`طلب رقم #${String(c.id).slice(0, 6)} — ${c.service_title}`}
              sub={`المستفيد: ${c.beneficiary_name ?? '—'} • ${ago(c.created_at)}`}
              chip={st.label}
              chipTone={st.tone}
            />
          );
        })
      ) : (
        <Empty>لا توجد حالات نشطة حالياً</Empty>
      )}
    </Panel>
    <Notice tone="info">المراقبة الحية تعتمد على تحديثات نظام التتبع اللحظي وموجات التوزيع الذكي.</Notice>
  </>;
}

const allFilterKeys = [
  'الكل',
  'قيد البحث',
  'تم الإسناد',
  'في الطريق',
  'وصل',
  'قيد التنفيذ',
  'مكتملة',
  'ملغاة',
  'غير مستجاب',
  'مرفوع للإشراف',
];

export function Requests({live}: {live: Live}) {
  const [f, setF] = useState('الكل');
  const [q, setQ] = useState('');
  const [selected, setSelected] = useState<RequestRow | null>(null);

  const filteredRaw = live.requests.filter(r => {
    const stLabel = statusConfig[r.status]?.label ?? r.status;
    const matchFilter = f === 'الكل' || stLabel === f;
    const matchQuery =
      !q ||
      r.id.toLowerCase().includes(q.toLowerCase()) ||
      (r.service_title ?? '').toLowerCase().includes(q.toLowerCase()) ||
      (r.beneficiary_name ?? '').toLowerCase().includes(q.toLowerCase()) ||
      stLabel.includes(q);
    return matchFilter && matchQuery;
  });

  const rows = filteredRaw.map(r => {
    return [
      <button
        key="id"
        className="ghost mono-code"
        onClick={() => setSelected(r)}
        title="عرض تفاصيل الطلب"
      >
        #{r.id.slice(0, 6)}
      </button>,
      <strong key="srv">{r.service_title ?? '—'}</strong>,
      r.beneficiary_name ?? '—',
      <StatusBadge key="st" status={r.status} />,
      <span key="tm" className="text-muted">{ago(r.created_at)}</span>,
    ];
  });

  return <>
    <div className="toolbar panel">
      <div className="filters-scroll">
        <div className="filters">
          {allFilterKeys.map(x => (
            <button key={x} className={'pill ' + (f === x ? 'on' : '')} onClick={() => setF(x)}>
              {x}
            </button>
          ))}
        </div>
      </div>
      <div className="search-wrap">
        <Icon name="search" size={16} className="search-ic"/>
        <input className="search" placeholder="بحث بالرقم أو الخدمة أو الاسم..." value={q} onChange={e => setQ(e.target.value)}/>
        {q && <button className="clear-search" onClick={() => setQ('')}>×</button>}
      </div>
    </div>

    <Panel
      title="سجل الطلبات"
      subtitle={`عرض ${filteredRaw.length} من أصل ${live.requests.length} طلب متوفر`}
      action={
        <span className="chip chip-info">{filteredRaw.length} نتيجة</span>
      }
    >
      {rows.length ? <Table head={reqHead} rows={rows}/> : <Empty>لا توجد طلبات مطابقة للبحث أو الفلتر المحدد</Empty>}
      {live.hasMore && (
        <div className="pager">
          <button disabled={live.more} onClick={live.loadMore} className="pill on">
            {live.more ? 'جارٍ تحميل المزيد...' : 'تحميل المزيد من الطلبات القديمة'}
          </button>
        </div>
      )}
    </Panel>
    <Notice tone="info">نظام التوزيع الذكي يمنع أي إسناد مزدوج للطلب ويضمن التوزيع لأقرب ممرض مؤهل معتمد.</Notice>
    <SidePanel
      open={!!selected}
      title={selected ? `تفاصيل الطلب #${selected.id.slice(0, 8)}` : ''}
      onClose={() => setSelected(null)}
    >
      {selected && (
        <div style={{display: 'flex', flexDirection: 'column', gap: 14}}>
          <div>
            <small className="hint">الحالة الحالية</small>
            <div style={{marginTop: 6}}><StatusBadge status={selected.status} /></div>
          </div>
          <div>
            <small className="hint">الخدمة المطلوبة</small>
            <p style={{margin: '4px 0', fontWeight: 700}}>{selected.service_title ?? '—'}</p>
          </div>
          <div>
            <small className="hint">المستفيد</small>
            <p style={{margin: '4px 0', fontWeight: 600}}>{selected.beneficiary_name ?? '—'}</p>
          </div>
          <div>
            <small className="hint">المعرّف الكامل</small>
            <p className="mono-code" dir="ltr" style={{margin: '4px 0'}}>{selected.id}</p>
          </div>
          <div>
            <RequestVisitRecord key={selected.id} id={selected.id} />
          </div>
        </div>
      )}
    </SidePanel>
  </>;
}

export function Finance({live}: {live: Live}) {
  const x = live.extra.finance, st: any[] = live.extra.settlements?.items ?? [];
  return <>
    <div className="stats">
      <Stat icon="cash" label="إجمالي قيمة الزيارات (الشهر)" value={`${n(Number(x?.visits_value ?? 0))} ل.س`} sub="قيمة الخدمات المنجزة"/>
      <Stat icon="wallet" label="صافي عمولة المنصة" value={`${n(Number(x?.commission ?? 0))} ل.س`} sub="النسبة المقتطعة للشركة"/>
      <Stat icon="users" label="مستحقات الممرضين" value={`${n(Number(x?.nurse_due ?? 0))} ل.س`} sub="أرباح الكوادر التمريضية"/>
      <Stat icon="alert" label="تسويات نقدية معلقة" value={n(Number(x?.pending_settlements ?? 0))} sub="بانتظار التحصيل أو الدفع"/>
    </div>
    <Panel title="سجل التسويات النقدية والمحاسبية" subtitle="حركات القبض والدفع المباشرة مع الممرضين">
      {st.length ? (
        <Table
          head={['الخدمة', 'رقم المرجع', 'القيمة', 'طريقة الدفع', 'الحالة']}
          rows={st.map(r => [
            r.service_title ?? 'خدمة تمريض',
            <span key="id" className="mono-code">{String(r.id).slice(0, 8)}</span>,
            `${n(Number(r.amount))} ل.س`,
            'نقدي (كاش)',
            <Chip key="st" tone={r.status === 'CONFIRMED' ? 'success' : 'warn'}>
              {r.status === 'CONFIRMED' ? 'مؤكدة' : 'قيد التسوية'}
            </Chip>,
          ])}
        />
      ) : <Empty>لا توجد تسويات مسجلة لهذا الشهر</Empty>}
    </Panel>
    <Notice tone="info">الأرقام مستخلصة ومحسوبة مباشرة من جدول الطلبات المكتملة وتخضع لضوابط التسوية النقدية المقرة (ADR-006).</Notice>
  </>;
}

export function WalletRec({live}: {live?: Live}) {
  return (
    <Panel
      title="مطابقة المحافظ والتسويات المالية"
      subtitle="آلية إدارة التدفقات النقدية وفق المعايير التنظيمية ADR-006"
    >
      <div className="wallet-card">
        <div className="wallet-icon-box">
          <Icon name="wallet" size={32}/>
        </div>
        <div className="wallet-info">
          <h3>نظام الدفع النقدي والتسويات الميدانية</h3>
          <p>
            وفقاً لقرار المعمارية التنظيمية <strong>ADR-006</strong>، لا يقوم تطبيق «تمريضي» بإصدار نقود إلكترونية أو فتح محافظ بقيم مخزنة من دون ترخيص مصرفي رسمي. يتم سداد قيمة الزيارات نقداً للممرض، وتسوية عمولة المنصة عبر سجل مستحقات الشركة.
          </p>
          <div className="wallet-actions">
            <span className="chip chip-success">التسويات النقدية فعّالة</span>
            {live?.navigate && (
              <button className="pill on" onClick={() => live.navigate!('dues')}>
                الانتقال إلى مستحقات وتسويات الممرضين ←
              </button>
            )}
          </div>
        </div>
      </div>
    </Panel>
  );
}

export function Reviews({live}: {live: Live}) {
  const x = live.extra.reviews;
  const [reviewsData, setReviewsData] = useState<any[]>([]);
  useEffect(() => {
    if (live?.token) {
      live.get('/v1/admin/reviews/items').then((r: any) => setReviewsData(r?.items || [])).catch(() => {});
    }
  }, [live?.token]);

  const sevConfig: Record<string, {label: string; tone: 'default' | 'warn' | 'danger' | 'purple'}> = {
    LOW: {label: 'منخفضة', tone: 'default'},
    MEDIUM: {label: 'متوسطة', tone: 'warn'},
    HIGH: {label: 'أولوية عالية', tone: 'danger'},
    CRITICAL: {label: 'حرجة للغاية', tone: 'danger'},
  };
  const items: any[] = x?.items ?? [];

  return <>
    <div className="stats">
      <Stat icon="star" label="متوسط تقييم الممرضين" value={x?.avg_rating ? `⭐ ${x.avg_rating} / 5` : '—'} sub="بناءً على تقييمات المرضى"/>
      <Stat icon="alert" label="شكاوى جديدة" value={pad(x?.new_complaints ?? 0)} sub="تحتاج إلى تدقيق المشرف"/>
      <Stat icon="heart" label="بلاغات السلامة الطبية" value={pad(x?.safety_reports ?? 0)} sub="تقارير سلامة المريض/الممرض"/>
      <Stat icon="check" label="بلاغات تم حلها" value={x?.resolved ?? 0} sub="أُغلقت بعد التحقق"/>
    </div>
    <Panel title="أحدث البلاغات وملاحظات الجودة" subtitle="مراقبة الالتزام المهني والشكاوى">
      {items.length ? (
        items.map(i => {
          const sc = sevConfig[i.severity] ?? {label: i.severity, tone: 'default'};
          return (
            <Row
              key={i.id}
              icon="alert"
              title={`بلاغ عن طلب #${String(i.request_id).slice(0, 6)}`}
              sub={i.description || 'لا يوجد وصف تفصيلي للبلاغ'}
              chip={i.status === 'OPEN' ? 'مفتوحة للمتابعة' : sc.label}
              chipTone={i.status === 'OPEN' ? 'warn' : sc.tone}
            />
          );
        })
      ) : <Empty>لا توجد بلاغات سلامة أو شكاوى مفتوحة ✓</Empty>}
    </Panel>
    <Panel title="تقييمات وملاحظات الزيارات المكتملة" subtitle="مراجعات المرضى وتقارير الممرضين المهنية">
      {reviewsData.length ? (
        <Table
          head={['التقييم', 'الطرف والمقيّم', 'الخدمة', 'الملاحظات والتقرير', 'التاريخ']}
          rows={reviewsData.map(r => [
            r.stars ? `⭐ ${r.stars} / 5` : 'تقرير مهني',
            r.reviewer_role === 'PATIENT' ? (
              <span key={r.id}><b>مريض:</b> {r.patient_name || r.patient_phone || '—'}<br/><small className="hint">للممرض: {r.nurse_name || r.nurse_phone}</small></span>
            ) : (
              <span key={r.id}><b>ممرض:</b> {r.nurse_name || r.nurse_phone || '—'}<br/><small className="hint">عن المريض: {r.patient_name || r.patient_phone}</small></span>
            ),
            r.service_title || '—',
            r.behavior_notes || '—',
            r.created_at ? String(r.created_at).slice(0, 10) : '—',
          ])}
        />
      ) : (
        <Empty>لا توجد تقييمات مسجلة بعد</Empty>
      )}
    </Panel>
    <Notice tone="info">تقييم المريض للممرض ينشر بعد مراجعته لحماية الخصوصية، وتقييم الممرض للمريض تقييم داخلي لغايات السلامة.</Notice>
  </>;
}

export function Reports({live}: {live?: Live}) {
  const downloadCsv = (filename: string, headers: string[], dataRows: string[][]) => {
    const csvContent =
      '\uFEFF' + // UTF-8 BOM so Excel opens Arabic correctly
      [headers.join(','), ...dataRows.map(r => r.map(cell => `"${(cell || '').replace(/"/g, '""')}"`).join(','))].join('\r\n');
    const blob = new Blob([csvContent], {type: 'text/csv;charset=utf-8;'});
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.setAttribute('href', url);
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  const exportRequests = () => {
    if (!live?.requests?.length) return;
    const headers = ['رقم الطلب', 'الخدمة', 'المستفيد', 'الحالة', 'تاريخ الإنشاء'];
    const rows = live.requests.map(r => [
      r.id,
      r.service_title ?? '',
      r.beneficiary_name ?? '',
      statusConfig[r.status]?.label ?? r.status,
      new Date(r.created_at).toLocaleString('ar-SY'),
    ]);
    downloadCsv(`طلبات_تمريضي_${new Date().toISOString().slice(0, 10)}.csv`, headers, rows);
  };

  const total = live?.requests?.length ?? 0;
  const completed = live?.requests?.filter(r => r.status === 'COMPLETED').length ?? 0;
  const cancelled = live?.requests?.filter(r => r.status === 'CANCELLED' || r.status === 'UNFULFILLED').length ?? 0;
  const activeNow = live?.requests?.filter(r => ['OFFERING', 'ASSIGNED', 'EN_ROUTE', 'ARRIVED', 'IN_SERVICE'].includes(r.status)).length ?? 0;

  return (
    <>
      <div className="stats">
        <Stat icon="chart" label="إجمالي الطلبات المسجلة" value={total} sub="في الجلسة الحالية"/>
        <Stat icon="check" label="نسبة الإنجاز الناجح" value={total > 0 ? `${Math.round((completed / total) * 100)}%` : '0%'} sub={`${completed} زيارة مكتملة`}/>
        <Stat icon="pulse" label="طلبات نشطة الآن" value={activeNow} sub="قيد المتابعة الميدانية"/>
        <Stat icon="alert" label="نسبة الإلغاء وعدم التلبية" value={total > 0 ? `${Math.round((cancelled / total) * 100)}%` : '0%'} sub={`${cancelled} طلب ملغى`}/>
      </div>

      <Panel
        title="تصدير البيانات والتقارير المجدولة"
        subtitle="استخراج الجداول بصيغة CSV تدعم اللغة العربية لبرنامج Microsoft Excel"
      >
        <div className="reports-grid">
          <div className="report-item">
            <div className="report-info">
              <h4>تقرير سجل طلبات الرعاية الكامل</h4>
              <p>يحتوي على كافة الحالات وأرقام الهواتف وأسماء المستفيدين وتواريخ الإنجاز.</p>
            </div>
            <button className="pill on" onClick={exportRequests} disabled={!total}>
              <Icon name="download" size={16}/> تصدير الطلبات (CSV)
            </button>
          </div>

          <div className="report-item">
            <div className="report-info">
              <h4>تقرير التسويات المالية والعمولات</h4>
              <p>تصدير حركات القبض النقدي وحصص الشركة وأرباح الممرضين المعتمدين.</p>
            </div>
            <button
              className="pill on"
              onClick={() => {
                const st: any[] = live?.extra?.settlements?.items ?? [];
                const headers = ['رقم التسوية', 'الخدمة', 'المبلغ (ل.س)', 'النوع', 'الحالة'];
                const rows = st.map(s => [s.id, s.service_title ?? '', s.amount, 'نقدي', s.status]);
                downloadCsv(`تسويات_تمريضي_${new Date().toISOString().slice(0, 10)}.csv`, headers, rows);
              }}
            >
              <Icon name="download" size={16}/> تصدير التسويات (CSV)
            </button>
          </div>
        </div>
      </Panel>
    </>
  );
}
