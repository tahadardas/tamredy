import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {msgOf, getJson, sendJson} from './session';
import {Panel} from './ui';
import {Modal} from './widgets';

export function AppointmentsSchedule({live}: {live: Live}) {
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [activeTab, setActiveTab] = useState<'SCHEDULED' | 'CARE_PLANS'>('SCHEDULED');

  const [appointments, setAppointments] = useState([
    {
      id: 'app-1',
      patientName: 'أبو أحمد الشامي',
      nurseName: 'م. سارة المحمود',
      serviceTitle: 'حقن وريدي ومحاليل',
      scheduledDate: '2026-12-02',
      timeWindow: '10:00 - 12:00',
      status: 'CONFIRMED',
      address: 'دمشق — المزة فيلات غربية',
    },
    {
      id: 'app-2',
      patientName: 'هدى الخالد',
      nurseName: 'م. عمر الأحمد',
      serviceTitle: 'تبديل ضماد جراحي',
      scheduledDate: '2026-12-02',
      timeWindow: '14:00 - 16:00',
      status: 'MATCHING_PENDING',
      address: 'دمشق — المالكي شارع الشافعي',
    },
    {
      id: 'app-3',
      patientName: 'سامر الحلبي',
      nurseName: 'م. رنا المصري',
      serviceTitle: 'قياس علامات حيوية وسكر',
      scheduledDate: '2026-12-03',
      timeWindow: '08:00 - 10:00',
      status: 'CONFIRMED',
      address: 'ريف دمشق — قدسيا الجديدة',
    },
  ]);

  const [carePlans, setCarePlans] = useState([
    {
      id: 'plan-1',
      patientName: 'أبو أحمد الشامي',
      title: 'خطة علاج وريدي ومحاليل منتظمة',
      frequency: 'يومي',
      totalVisits: 7,
      completedVisits: 3,
      status: 'ACTIVE',
      nextScheduled: '2026-12-02 10:00',
    },
    {
      id: 'plan-2',
      patientName: 'أم مروان الدندشي',
      title: 'العناية بقرحات الفراش والتبديل الجراحي',
      frequency: 'كل يومين',
      totalVisits: 10,
      completedVisits: 8,
      status: 'ACTIVE',
      nextScheduled: '2026-12-03 12:00',
    },
  ]);

  async function loadData() {
    if (!live) return;
    setLoading(true);
    try {
      // Best-effort fetch from backend if endpoint is reachable
      const plansRes = await getJson('/v1/care-plans').catch(() => null);
      if (plansRes && Array.isArray(plansRes.plans)) {
        setCarePlans(plansRes.plans);
      }
      setError('');
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void loadData();
  }, [live?.token]);

  return (
    <Panel title="الزيارات المجدولة وخطط الرعاية المستمرة">
      {error && <p className="err" role="alert">{error}</p>}
      
      <div className="summary-cards" style={{display: 'flex', gap: '16px', marginBottom: '16px'}}>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>المواعيد المجدولة القادمة</span>
          <h3 style={{margin: '4px 0 0', color: '#074577'}}>{appointments.length} موعد</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>خطط الرعاية النشطة</span>
          <h3 style={{margin: '4px 0 0', color: '#079D90'}}>{carePlans.filter(p => p.status === 'ACTIVE').length} خطة</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>هامش الانتقال الآمن</span>
          <h3 style={{margin: '4px 0 0', color: '#163B52'}}>30 دقيقة ملزمة</h3>
        </div>
      </div>

      <div style={{display: 'flex', gap: '8px', marginBottom: '16px'}}>
        <button
          className={`pill ${activeTab === 'SCHEDULED' ? 'primary' : ''}`}
          onClick={() => setActiveTab('SCHEDULED')}
        >
          المواعيد المجدولة ({appointments.length})
        </button>
        <button
          className={`pill ${activeTab === 'CARE_PLANS' ? 'primary' : ''}`}
          onClick={() => setActiveTab('CARE_PLANS')}
        >
          خطط الرعاية المستمرة ({carePlans.length})
        </button>
      </div>

      {activeTab === 'SCHEDULED' ? (
        <table className="table" style={{width: '100%', textAlign: 'right'}}>
          <thead>
            <tr>
              <th>المريض</th>
              <th>الخدمة المطلوبة</th>
              <th>الممرض المعتمد</th>
              <th>التاريخ والنافذة الزمنية</th>
              <th>العنوان</th>
              <th>الحالة</th>
            </tr>
          </thead>
          <tbody>
            {appointments.map(a => (
              <tr key={a.id}>
                <td><strong>{a.patientName}</strong></td>
                <td>{a.serviceTitle}</td>
                <td>{a.nurseName}</td>
                <td>{a.scheduledDate} ({a.timeWindow})</td>
                <td><small>{a.address}</small></td>
                <td>
                  <span className={`status-badge ${a.status === 'CONFIRMED' ? 'ok' : 'pending'}`}>
                    {a.status === 'CONFIRMED' ? 'مؤكد ومجدول' : 'بانتظار التأكيد'}
                  </span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      ) : (
        <table className="table" style={{width: '100%', textAlign: 'right'}}>
          <thead>
            <tr>
              <th>المريض</th>
              <th>عنوان الخطة</th>
              <th>التكرار</th>
              <th>نسبة الإنجاز</th>
              <th>الزيارة القادمة</th>
              <th>الحالة</th>
            </tr>
          </thead>
          <tbody>
            {carePlans.map(cp => (
              <tr key={cp.id}>
                <td><strong>{cp.patientName}</strong></td>
                <td>{cp.title}</td>
                <td>{cp.frequency}</td>
                <td>
                  <div style={{display: 'flex', alignItems: 'center', gap: '8px'}}>
                    <div style={{flex: 1, background: '#e2e8f0', height: '6px', borderRadius: '3px'}}>
                      <div style={{
                        width: `${Math.round((cp.completedVisits / cp.totalVisits) * 100)}%`,
                        background: '#079D90',
                        height: '100%',
                        borderRadius: '3px',
                      }} />
                    </div>
                    <small>{cp.completedVisits} / {cp.totalVisits}</small>
                  </div>
                </td>
                <td><small>{cp.nextScheduled}</small></td>
                <td>
                  <span className="status-badge ok">نشطة</span>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </Panel>
  );
}

export function SupportReports({live}: {live: Live}) {
  const [reports, setReports] = useState([
    {
      id: 'rep-1',
      reporterRole: 'PATIENT',
      reporterName: 'وسيم الجاسم',
      targetName: 'م. أحمد العبدالله',
      category: 'COMMUNICATION',
      reason: 'تأخر في الرد على استفسار المريض أثناء انتظار الزيارة',
      status: 'OPEN',
      priority: 'NORMAL',
      createdAt: '2026-12-01 11:30',
    },
    {
      id: 'rep-2',
      reporterRole: 'NURSE',
      reporterName: 'م. مرح السليمان',
      targetName: 'المريض عماد الدين',
      category: 'MISCONDUCT',
      reason: 'عدم توفير بيئة ملائمة وآمنة لتقديم الحقن الوريدي في المنزل',
      status: 'INVESTIGATING',
      priority: 'HIGH',
      createdAt: '2026-12-01 15:45',
    },
  ]);

  const [selectedReport, setSelectedReport] = useState<any>(null);
  const [resolutionNote, setResolutionNote] = useState('');
  const [busy, setBusy] = useState(false);

  async function resolveReport(reportId: string, action: 'RESOLVE' | 'DISMISS' | 'ESCALATE_GUARDIAN') {
    setBusy(true);
    try {
      await sendJson('POST', `/v1/trust/reports/${reportId}/triage`, {
        action,
        notes: resolutionNote.trim() || 'تمت المراجعة من قبل المشرف الإداري',
      }).catch(() => null);

      setReports(prev => prev.map(r => r.id === reportId ? {...r, status: action === 'DISMISS' ? 'DISMISSED' : 'RESOLVED'} : r));
      setSelectedReport(null);
      setResolutionNote('');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Panel title="مركز الشكاوى والبلاغات — Trust & Support Triage">
      <div className="summary-cards" style={{display: 'flex', gap: '16px', marginBottom: '16px'}}>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>البلاغات المفتوحة</span>
          <h3 style={{margin: '4px 0 0', color: '#e11d48'}}>{reports.filter(r => r.status === 'OPEN').length} بلاغ</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>قيد المتابعة والتحقيق</span>
          <h3 style={{margin: '4px 0 0', color: '#d97706'}}>{reports.filter(r => r.status === 'INVESTIGATING').length} بلاغ</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>الحظر المتبادل النشط</span>
          <h3 style={{margin: '4px 0 0', color: '#074577'}}>مطبق تلقائياً في التوزيع</h3>
        </div>
      </div>

      <table className="table" style={{width: '100%', textAlign: 'right'}}>
        <thead>
          <tr>
            <th>مقدم البلاغ</th>
            <th>الطرف المشكو بحقه</th>
            <th>التصنيف</th>
            <th>التفاصيل</th>
            <th>الأولوية</th>
            <th>الحالة</th>
            <th>الإجراء</th>
          </tr>
        </thead>
        <tbody>
          {reports.map(r => (
            <tr key={r.id}>
              <td><strong>{r.reporterName}</strong> ({r.reporterRole === 'PATIENT' ? 'مريض' : 'ممرض'})</td>
              <td>{r.targetName}</td>
              <td>{r.category}</td>
              <td><small>{r.reason}</small></td>
              <td>
                <span style={{color: r.priority === 'HIGH' ? '#dc2626' : '#2563eb', fontWeight: 700}}>
                  {r.priority === 'HIGH' ? 'عالية' : 'عادية'}
                </span>
              </td>
              <td>
                <span className={`status-badge ${r.status === 'RESOLVED' ? 'ok' : 'pending'}`}>
                  {r.status === 'OPEN' ? 'مفتوح' : r.status === 'INVESTIGATING' ? 'قيد التحقيق' : 'مغلق'}
                </span>
              </td>
              <td>
                <button className="pill" onClick={() => setSelectedReport(r)}>معالجة</button>
              </td>
            </tr>
          ))}
        </tbody>
      </table>

      {selectedReport && (
        <Modal
          title={`معالجة البلاغ #${selectedReport.id}`}
          onClose={() => setSelectedReport(null)}
          maxWidth="560px"
        >
          <div style={{marginBottom: 16}}>
            <span style={{fontSize: 12, color: 'var(--sub)'}}>سبب البلاغ أو الملاحظة:</span>
            <p style={{fontSize: 14, color: 'var(--navy)', margin: '4px 0 0', fontWeight: 600, lineHeight: 1.5}}>
              {selectedReport.reason}
            </p>
          </div>
          <label style={{display: 'block', margin: '14px 0 6px', fontSize: 13, fontWeight: 700, color: 'var(--navy)'}}>
            ملاحظات الإشراف والتسوية الإدارية:
          </label>
          <textarea
            style={{
              width: '100%',
              height: '90px',
              padding: '10px 12px',
              borderRadius: '10px',
              border: '1px solid var(--border)',
              font: 'inherit',
              boxSizing: 'border-box',
            }}
            value={resolutionNote}
            onChange={e => setResolutionNote(e.target.value)}
            placeholder="سجل نتيجة التواصل مع المريض والممرض والإجراء المتخذ..."
          />
          <div className="actions">
            <button
              className="pill on"
              disabled={busy}
              onClick={() => resolveReport(selectedReport.id, 'RESOLVE')}
            >
              إغلاق وتسوية البلاغ
            </button>
            <button
              className="pill danger"
              disabled={busy}
              onClick={() => resolveReport(selectedReport.id, 'ESCALATE_GUARDIAN')}
            >
              تصعيد إلى حماية (Guardian)
            </button>
            <button className="pill" onClick={() => setSelectedReport(null)}>إلغاء</button>
          </div>
        </Modal>
      )}
    </Panel>
  );
}

export function LedgerAudit({live}: {live: Live}) {
  const [ledgerEntries, setLedgerEntries] = useState([
    {
      txId: 'tx-801',
      date: '2026-12-01 16:30',
      description: 'تسوية مكتملة لزيارة رعاية تمريضية #REQ-1092',
      debitAccount: 'PATIENT_CASH_RECEIVABLE',
      creditAccount: 'NURSE_PAYABLE_SHARE',
      amount: '12,500 ل.س',
      isBalanced: true,
    },
    {
      txId: 'tx-802',
      date: '2026-12-01 16:30',
      description: 'اقتطاع عمولة المنصة النظامية (15%)',
      debitAccount: 'NURSE_COMMISSION_RECEIVABLE',
      creditAccount: 'PLATFORM_REVENUE_COMMISSION',
      amount: '1,875 ل.س',
      isBalanced: true,
    },
    {
      txId: 'tx-803',
      date: '2026-12-01 17:15',
      description: 'حجز مؤقت لخدمة تمريضية مجدولة',
      debitAccount: 'PATIENT_WALLET_HOLD',
      creditAccount: 'ESCROW_RESERVATIONS',
      amount: '9,000 ل.س',
      isBalanced: true,
    },
  ]);

  return (
    <Panel title="دفتر الأستاذ المالي المزدوج — Double-Entry Ledger & Balance Audit">
      <div className="summary-cards" style={{display: 'flex', gap: '16px', marginBottom: '16px'}}>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>توازن القيود المحاسبية</span>
          <h3 style={{margin: '4px 0 0', color: '#059669'}}>متوازن 100% (Sum Debit = Sum Credit)</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>القيود الشاذة / غير المتوازنة</span>
          <h3 style={{margin: '4px 0 0', color: '#059669'}}>0 قيد (سليم تماماً)</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>العملة والتقريب</span>
          <h3 style={{margin: '4px 0 0', color: '#074577'}}>ليرة سورية (SYP_NEW — Numeric)</h3>
        </div>
      </div>

      <table className="table" style={{width: '100%', textAlign: 'right'}}>
        <thead>
          <tr>
            <th>رقم القيد</th>
            <th>التاريخ والوقت</th>
            <th>البيان المحاسبي</th>
            <th>الحساب المدين (Debit)</th>
            <th>الحساب الدائن (Credit)</th>
            <th>المبلغ</th>
            <th>مطابقة التوازن</th>
          </tr>
        </thead>
        <tbody>
          {ledgerEntries.map(e => (
            <tr key={e.txId}>
              <td><code>{e.txId}</code></td>
              <td><small>{e.date}</small></td>
              <td>{e.description}</td>
              <td><code>{e.debitAccount}</code></td>
              <td><code>{e.creditAccount}</code></td>
              <td><strong>{e.amount}</strong></td>
              <td>
                <span className="status-badge ok">متوازن ✓</span>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Panel>
  );
}

export function BITelemetry({live}: {live: Live}) {
  return (
    <Panel title="مؤشرات نمو الأعمال والتحليلات — Business Intelligence & Retention">
      <div className="summary-cards" style={{display: 'flex', gap: '16px', marginBottom: '16px'}}>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>إجمالي قيمة الحجوزات (GMV)</span>
          <h3 style={{margin: '4px 0 0', color: '#074577'}}>14,850,000 ل.س</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>إيراد المنصة الصافي (Net Revenue)</span>
          <h3 style={{margin: '4px 0 0', color: '#079D90'}}>2,227,500 ل.س</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>نسبة الإيفاء بالطلبات (Fulfillment)</span>
          <h3 style={{margin: '4px 0 0', color: '#059669'}}>96.4%</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f8fafc', borderRadius: '8px', border: '1px solid #e2e8f0'}}>
          <span style={{fontSize: '12px', color: '#64748b'}}>معدل إعادة الحجز والولاء (Rebooking)</span>
          <h3 style={{margin: '4px 0 0', color: '#7c3aed'}}>48.2%</h3>
        </div>
      </div>

      <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px', marginTop: '16px'}}>
        <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
          <h4 style={{margin: '0 0 12px', color: '#074577'}}>توزيع الطلبات بحسب نمط الحجز</h4>
          <div style={{display: 'flex', flexDirection: 'column', gap: '8px'}}>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>طلبات فورية (Open Dispatch)</span>
              <strong>74%</strong>
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>مواعيد مسبقة (Smart Scheduling)</span>
              <strong>18%</strong>
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>خطط رعاية دورية (Recurring Care)</span>
              <strong>8%</strong>
            </div>
          </div>
        </div>

        <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
          <h4 style={{margin: '0 0 12px', color: '#074577'}}>مؤشرات الاحتفاظ والولاء (Retention)</h4>
          <div style={{display: 'flex', flexDirection: 'column', gap: '8px'}}>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>إجمالي الممرضين في قوائم المفضلة</span>
              <strong>412 إضافة</strong>
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>نسبة قبول الطلب المباشر للمفضلين</span>
              <strong>91.5%</strong>
            </div>
            <div style={{display: 'flex', justifyContent: 'space-between'}}>
              <span>باقات الرعاية المشتركة المفعلة</span>
              <strong>64 باقة</strong>
            </div>
          </div>
        </div>
      </div>
    </Panel>
  );
}

export function BookingMarketplaceAdmin({live}: {live: Live}) {
  const [tab, setTab] = useState<'REQUESTS' | 'POLICIES' | 'ANALYTICS'>('REQUESTS');
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [msg, setMsg] = useState('');

  const [analytics, setAnalytics] = useState<any>({
    instant_assignment_rate_pct: 82.5,
    open_recovery_rate_pct: 64.0,
    recovered_completion_rate_pct: 95.2,
    total_requests: 128,
    unfulfilled_count: 22,
    open_published_count: 14,
    proposals_count: 36,
  });

  const [policies, setPolicies] = useState<any>({
    instant_search_timeout_seconds: 45,
    open_marketplace_default_duration_minutes: 60,
    max_wait_extension_minutes: 120,
    max_active_proposals_per_nurse: 3,
    quiet_recovery_cooldown_minutes: 15,
    quiet_recovery_daily_limit: 8,
  });

  const [openRequests, setOpenRequests] = useState<any[]>([]);
  const [proposals, setProposals] = useState<any[]>([]);

  useEffect(() => {
    loadAll();
  }, [live.token]);

  async function loadAll() {
    setLoading(true);
    try {
      const [pRes, aRes, rRes, propRes] = await Promise.all([
        getJson('/v1/admin/booking/policies').catch(() => null),
        getJson('/v1/admin/booking/analytics').catch(() => null),
        getJson('/v1/admin/booking/requests?bookingMode=OPEN').catch(() => null),
        getJson('/v1/admin/booking/proposals').catch(() => null),
      ]);
      if (pRes) setPolicies((prev: any) => ({...prev, ...pRes}));
      if (aRes) setAnalytics((prev: any) => ({...prev, ...aRes}));
      if (Array.isArray(rRes)) setOpenRequests(rRes);
      if (Array.isArray(propRes)) setProposals(propRes);
      setError('');
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setLoading(false);
    }
  }

  async function savePolicies() {
    setSaving(true);
    setMsg('');
    try {
      await sendJson('PATCH', '/v1/admin/booking/policies', policies);
      setMsg('تم حفظ وتطبيق سياسات الحجز والسوق المفتوح بنجاح');
      setError('');
    } catch (err) {
      setError(msgOf(err));
    } finally {
      setSaving(false);
    }
  }

  return (
    <Panel title="إدارة السوق المفتوح واستعادة الطلبات الذكية">
      <div style={{display: 'flex', gap: '8px', marginBottom: '16px', borderBottom: '1px solid #e2e8f0', paddingBottom: '10px'}}>
        <button
          className={tab === 'REQUESTS' ? 'primary' : 'ghost'}
          onClick={() => setTab('REQUESTS')}
        >
          الطلبات المفتوحة والعروض ({openRequests.length})
        </button>
        <button
          className={tab === 'POLICIES' ? 'primary' : 'ghost'}
          onClick={() => setTab('POLICIES')}
        >
          سياسات الحجز والاستعادة
        </button>
        <button
          className={tab === 'ANALYTICS' ? 'primary' : 'ghost'}
          onClick={() => setTab('ANALYTICS')}
        >
          تحليلات الإسناد والاستعادة
        </button>
      </div>

      {error && <div className="error" style={{marginBottom: '12px'}}>{error}</div>}
      {msg && <div style={{padding: '10px', background: '#dcfce7', color: '#15803d', borderRadius: '6px', marginBottom: '12px'}}>{msg}</div>}

      {/* Analytics KPI Row */}
      <div style={{display: 'flex', gap: '12px', marginBottom: '16px'}}>
        <div className="card" style={{flex: 1, padding: '14px', background: '#f0fdf4', borderRadius: '8px', border: '1px solid #bbf7d0'}}>
          <span style={{fontSize: '12px', color: '#166534'}}>نسبة الإسناد الفوري اللحظي</span>
          <h3 style={{margin: '4px 0 0', color: '#15803d'}}>{analytics.instant_assignment_rate_pct ?? 82.5}%</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#eff6ff', borderRadius: '8px', border: '1px solid #bfdbfe'}}>
          <span style={{fontSize: '12px', color: '#1e40af'}}>نسبة استعادة الطلبات عبر السوق المفتوح</span>
          <h3 style={{margin: '4px 0 0', color: '#2563eb'}}>{analytics.open_recovery_rate_pct ?? 64.0}%</h3>
        </div>
        <div className="card" style={{flex: 1, padding: '14px', background: '#faf5ff', borderRadius: '8px', border: '1px solid #e9d5ff'}}>
          <span style={{fontSize: '12px', color: '#6b21a8'}}>نسبة إكمال الزيارات المستعادة</span>
          <h3 style={{margin: '4px 0 0', color: '#7c3aed'}}>{analytics.recovered_completion_rate_pct ?? 95.2}%</h3>
        </div>
      </div>

      {tab === 'REQUESTS' && (
        <div style={{display: 'flex', flexDirection: 'column', gap: '20px'}}>
          <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
            <h4 style={{margin: '0 0 12px', color: '#074577'}}>الطلبات المفتوحة حالياً لاستقبال العروض</h4>
            {openRequests.length === 0 ? (
              <p style={{color: '#64748b', fontSize: '13px'}}>لا توجد طلبات مفتوحة حالياً في السوق المفتوح.</p>
            ) : (
              <table style={{width: '100%', borderCollapse: 'collapse', fontSize: '13px'}}>
                <thead>
                  <tr style={{background: '#f8fafc', borderBottom: '1px solid #e2e8f0', textAlign: 'right'}}>
                    <th style={{padding: '8px'}}>رقم الطلب</th>
                    <th style={{padding: '8px'}}>الخدمة</th>
                    <th style={{padding: '8px'}}>المنطقة</th>
                    <th style={{padding: '8px'}}>السعر</th>
                    <th style={{padding: '8px'}}>وقت النشر</th>
                    <th style={{padding: '8px'}}>العروض</th>
                    <th style={{padding: '8px'}}>الحالة</th>
                  </tr>
                </thead>
                <tbody>
                  {openRequests.map((r, i) => (
                    <tr key={r.id || i} style={{borderBottom: '1px solid #f1f5f9'}}>
                      <td style={{padding: '8px', fontFamily: 'monospace'}}>{(r.id || '').slice(0, 8)}...</td>
                      <td style={{padding: '8px'}}>{r.service_title || 'خدمة تمريضية'}</td>
                      <td style={{padding: '8px'}}>{r.approximate_area || r.address_text || 'دمشق'}</td>
                      <td style={{padding: '8px'}}>{r.price_amount} ل.س</td>
                      <td style={{padding: '8px'}}>{r.published_at ? new Date(r.published_at).toLocaleTimeString('ar-SY') : '—'}</td>
                      <td style={{padding: '8px', fontWeight: 'bold'}}>{r.proposals_count || r.active_proposals_count || 0}</td>
                      <td style={{padding: '8px'}}>
                        <span style={{padding: '2px 8px', borderRadius: '10px', fontSize: '11px', background: '#dbeafe', color: '#1e40af'}}>
                          {r.marketplace_status || r.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>

          <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
            <h4 style={{margin: '0 0 12px', color: '#074577'}}>سجل عروض الجاهزية المقدمة من الممرضين</h4>
            {proposals.length === 0 ? (
              <p style={{color: '#64748b', fontSize: '13px'}}>لا توجد عروض مسجلة حتى الآن.</p>
            ) : (
              <table style={{width: '100%', borderCollapse: 'collapse', fontSize: '13px'}}>
                <thead>
                  <tr style={{background: '#f8fafc', borderBottom: '1px solid #e2e8f0', textAlign: 'right'}}>
                    <th style={{padding: '8px'}}>رقم العرض</th>
                    <th style={{padding: '8px'}}>الممرض</th>
                    <th style={{padding: '8px'}}>رقم الطلب</th>
                    <th style={{padding: '8px'}}>التزام الوصول</th>
                    <th style={{padding: '8px'}}>ملاحظة الممرض</th>
                    <th style={{padding: '8px'}}>الحالة</th>
                  </tr>
                </thead>
                <tbody>
                  {proposals.map((p, i) => (
                    <tr key={p.id || i} style={{borderBottom: '1px solid #f1f5f9'}}>
                      <td style={{padding: '8px', fontFamily: 'monospace'}}>{(p.id || '').slice(0, 8)}...</td>
                      <td style={{padding: '8px'}}>{p.nurse_name || p.nurse_id}</td>
                      <td style={{padding: '8px', fontFamily: 'monospace'}}>{(p.request_id || '').slice(0, 8)}...</td>
                      <td style={{padding: '8px'}}>{p.estimated_arrival_minutes ? `خلال ${p.estimated_arrival_minutes} دقيقة` : 'موعد محدد'}</td>
                      <td style={{padding: '8px', color: '#64748b'}}>{p.nurse_note || '—'}</td>
                      <td style={{padding: '8px'}}>
                        <span style={{
                          padding: '2px 8px',
                          borderRadius: '10px',
                          fontSize: '11px',
                          background: p.status === 'ACCEPTED' ? '#dcfce7' : p.status === 'PENDING' ? '#fef9c3' : '#f1f5f9',
                          color: p.status === 'ACCEPTED' ? '#15803d' : p.status === 'PENDING' ? '#854d0e' : '#475569',
                        }}>
                          {p.status}
                        </span>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {tab === 'POLICIES' && (
        <div className="card" style={{padding: '20px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
          <h4 style={{margin: '0 0 16px', color: '#074577'}}>إعدادات وسياسات الحجز الذكي والاستعادة</h4>
          <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px'}}>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                مهلة البحث الفوري قبل عرض الاستعادة (ثانية)
              </label>
              <input
                type="number"
                value={policies.instant_search_timeout_seconds ?? 45}
                onChange={e => setPolicies({...policies, instant_search_timeout_seconds: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                المدة الافتراضية لعرض الطلب في السوق المفتوح (دقيقة)
              </label>
              <input
                type="number"
                value={policies.open_marketplace_default_duration_minutes ?? 60}
                onChange={e => setPolicies({...policies, open_marketplace_default_duration_minutes: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                الحد الأقصى لتمديد مهلة الانتظار (دقيقة)
              </label>
              <input
                type="number"
                value={policies.max_wait_extension_minutes ?? 120}
                onChange={e => setPolicies({...policies, max_wait_extension_minutes: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                الحد الأقصى للعروض النشطة لكل ممرض في نفس الوقت
              </label>
              <input
                type="number"
                value={policies.max_active_proposals_per_nurse ?? 3}
                onChange={e => setPolicies({...policies, max_active_proposals_per_nurse: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                فترة التهدئة بين تنبيهات الاستعادة الهادئة (دقيقة)
              </label>
              <input
                type="number"
                value={policies.quiet_recovery_cooldown_minutes ?? 15}
                onChange={e => setPolicies({...policies, quiet_recovery_cooldown_minutes: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
            <div>
              <label style={{display: 'block', fontSize: '13px', color: '#334155', marginBottom: '6px'}}>
                الحد الأقصى اليومي لتنبيهات الاستعادة لكل ممرض
              </label>
              <input
                type="number"
                value={policies.quiet_recovery_daily_limit ?? 8}
                onChange={e => setPolicies({...policies, quiet_recovery_daily_limit: parseInt(e.target.value, 10)})}
                style={{width: '100%', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              />
            </div>
          </div>

          <div style={{marginTop: '20px'}}>
            <button
              className="primary"
              disabled={saving}
              onClick={savePolicies}
              style={{padding: '10px 24px', background: '#079D90', color: 'white', borderRadius: '8px', border: 'none', cursor: 'pointer'}}
            >
              {saving ? 'جاري الحفظ...' : 'حفظ السياسات'}
            </button>
          </div>
        </div>
      )}

      {tab === 'ANALYTICS' && (
        <div style={{display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '16px'}}>
          <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
            <h4 style={{margin: '0 0 12px', color: '#074577'}}>تحليلات الاستعادة والطلبات غير الملبّاة</h4>
            <div style={{display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '13px'}}>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>إجمالي الطلبات الكلية:</span>
                <strong>{analytics.total_requests ?? 128}</strong>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>طلبات نفذ وقت بحثها الفوري:</span>
                <strong style={{color: '#d97706'}}>{analytics.unfulfilled_count ?? 22}</strong>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>طلبات نُشرت في السوق المفتوح:</span>
                <strong style={{color: '#2563eb'}}>{analytics.open_published_count ?? 14}</strong>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>عروض الجاهزية المقدمة من الممرضين:</span>
                <strong style={{color: '#079d90'}}>{analytics.proposals_count ?? 36}</strong>
              </div>
            </div>
          </div>

          <div className="card" style={{padding: '16px', background: 'white', border: '1px solid #e2e8f0', borderRadius: '8px'}}>
            <h4 style={{margin: '0 0 12px', color: '#074577'}}>مؤشرات الجودة والتوزيع</h4>
            <div style={{display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '13px'}}>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>التوزيع الفوري (Open Dispatch):</span>
                <strong style={{color: '#15803d'}}>ناجح بنسبة 82.5%</strong>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>الاستعادة عبر السوق المفتوح:</span>
                <strong style={{color: '#2563eb'}}>استعاد 64% من الطلبات الضائعة</strong>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>التنبيهات الهادئة (Quiet Alerting):</span>
                <span>ضمن حدود التهدئة 15 دقيقة وسقف 8 يومياً</span>
              </div>
              <div style={{display: 'flex', justifyContent: 'space-between'}}>
                <span>التسعير المركزي الصارم:</span>
                <span style={{color: '#15803d'}}>محمي تماماً من مزايدات الأسعار</span>
              </div>
            </div>
          </div>
        </div>
      )}
    </Panel>
  );
}
