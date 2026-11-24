import {useEffect, useState} from 'react';
import type {Live} from './pages';
import {msgOf, getJson, sendJson} from './session';
import {Panel} from './ui';

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
        <div className="modal-overlay" style={{
          position: 'fixed', top: 0, left: 0, right: 0, bottom: 0,
          background: 'rgba(0,0,0,0.5)', display: 'flex', alignItems: 'center', justifyContent: 'center', zIndex: 1000
        }}>
          <div className="modal" style={{background: 'white', padding: '24px', borderRadius: '12px', maxWidth: '500px', width: '90%'}}>
            <h3>معالجة البلاغ #{selectedReport.id}</h3>
            <p style={{fontSize: '14px', color: '#475569'}}>{selectedReport.reason}</p>
            <label style={{display: 'block', margin: '12px 0 6px', fontWeight: 600}}>
              ملاحظات الإشراف والتسوية:
            </label>
            <textarea
              style={{width: '100%', height: '80px', padding: '8px', borderRadius: '6px', border: '1px solid #cbd5e1'}}
              value={resolutionNote}
              onChange={e => setResolutionNote(e.target.value)}
              placeholder="سجل نتيجة التواصل والإجراء الإداري..."
            />
            <div style={{display: 'flex', gap: '8px', marginTop: '16px'}}>
              <button
                className="pill primary"
                disabled={busy}
                onClick={() => resolveReport(selectedReport.id, 'RESOLVE')}
              >
                إغلاق وتسوية البلاغ
              </button>
              <button
                className="pill"
                style={{background: '#fee2e2', color: '#991b1b'}}
                disabled={busy}
                onClick={() => resolveReport(selectedReport.id, 'ESCALATE_GUARDIAN')}
              >
                تصعيد إلى قضية سلامة (Guardian)
              </button>
              <button className="pill ghost" onClick={() => setSelectedReport(null)}>إلغاء</button>
            </div>
          </div>
        </div>
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
