import React, { useEffect, useState } from 'react';
import type { Live } from './pages';
import { Notice, Panel } from './ui';
import { msgOf } from './session';

export function DispatchMonitor({ live }: { live: Live }) {
  const [data, setData] = useState<any>(null);
  const [fcmHealth, setFcmHealth] = useState<any>(null);
  const [loading, setLoading] = useState(false);
  const [err, setErr] = useState('');
  const [selectedRequestId, setSelectedRequestId] = useState<string | null>(null);
  const [requestDetail, setRequestDetail] = useState<any>(null);
  const [detailLoading, setDetailLoading] = useState(false);

  const load = async () => {
    if (!live) return;
    setLoading(true);
    try {
      const [diag, fcm] = await Promise.all([
        live.get('/v1/admin/dispatch/diagnostics'),
        live.get('/v1/admin/notifications/health'),
      ]);
      setData(diag);
      setFcmHealth(fcm);
      setErr('');
    } catch (e) {
      setErr(msgOf(e));
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    void load();
    const timer = setInterval(() => { void load(); }, 10000);
    return () => clearInterval(timer);
  }, [live?.token]);

  const inspectRequest = async (id: string) => {
    setSelectedRequestId(id);
    setDetailLoading(true);
    try {
      const res = await live.get(`/v1/admin/dispatch/requests/${id}`);
      setRequestDetail(res);
    } catch (e) {
      alert('تعذر جلب تفاصيل الطلب: ' + msgOf(e));
    } finally {
      setDetailLoading(false);
    }
  };

  const exportReport = async () => {
    try {
      const rep = await live.get('/v1/admin/dispatch/export?hours=24');
      const blob = new Blob([JSON.stringify(rep, null, 2)], { type: 'application/json' });
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = `tamreedy-dispatch-diagnostics-${new Date().toISOString().split('T')[0]}.json`;
      a.click();
      URL.revokeObjectURL(url);
    } catch (e) {
      alert('تعذر تصدير التقرير: ' + msgOf(e));
    }
  };

  const m = data?.metrics ?? {};
  const worker = data?.worker ?? {};
  const logs = data?.recentLogs ?? [];
  const tokenTotal = Object.values(fcmHealth?.platformTokens ?? {}).reduce((acc: number, val: any) => acc + Number(val || 0), 0);

  return (
    <div className="dispatch-monitor">
      {err && <Notice tone="danger">{err}</Notice>}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <div>
          <h2 style={{ margin: 0, fontSize: 20, fontWeight: 800, color: '#1E293B' }}>
            مراقبة التوزيع المباشر وصحة الإشعارات
          </h2>
          <p style={{ margin: '4px 0 0', color: '#64748B', fontSize: 13 }}>
            تتبع لحظي لمحرك المطابقة الجغرافية (Worker)، أسباب استبعاد الممرضين، وتدفق إشعارات FCM وSocket.IO.
          </p>
        </div>
        <div style={{ display: 'flex', gap: 8 }}>
          <button className="btn btn-secondary" onClick={exportReport} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span>📥</span> تصدير تقرير التشخيص التقني
          </button>
          <button className="btn btn-primary" onClick={load} disabled={loading} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
            <span style={{ display: 'inline-block', transform: loading ? 'rotate(180deg)' : 'none', transition: '0.3s' }}>🔄</span>
            {loading ? 'جاري التحديث...' : 'تحديث فوري'}
          </button>
        </div>
      </div>

      {/* Primary KPI Grid (12 Indicators per Section 10) */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 12, marginBottom: 20 }}>
        <div className="card" style={{ padding: 14, borderRight: '4px solid #2563EB' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>الطلبات قيد البحث</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#1E293B' }}>{m.active_searches ?? 0}</div>
          <div style={{ fontSize: 11, color: '#2563EB' }}>موجات الإسناد جارية</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #DC2626' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>طلبات دون ممرض (24س)</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#DC2626' }}>{m.unfulfilled_24h ?? 0}</div>
          <div style={{ fontSize: 11, color: '#64748B' }}>استنفدت جميع الموجات</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #059669' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>الممرضون الجاهزون فعلياً</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#059669' }}>{m.ready_nurses ?? 0}</div>
          <div style={{ fontSize: 11, color: '#059669' }}>مؤهلون وموقعهم متزامن &lt;120ث</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #6366F1' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>الممرضون المتاحون</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#1E293B' }}>{m.available_nurses ?? 0}</div>
          <div style={{ fontSize: 11, color: '#64748B' }}>من إجمالي {m.total_nurses ?? 0} ممرض</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #F59E0B' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>ممرضون بموقع قديم</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#D97706' }}>{m.stale_location_nurses ?? 0}</div>
          <div style={{ fontSize: 11, color: '#D97706' }}>لم يرسلوا GPS منذ &gt;120ث</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #EF4444' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>ممرضون بنبض منقطع</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#DC2626' }}>{m.stale_heartbeat_nurses ?? 0}</div>
          <div style={{ fontSize: 11, color: '#DC2626' }}>نبض الاتصال &gt;60 ثانية</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #8B5CF6' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>عروض أُنشئت اليوم</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#1E293B' }}>{m.offers_today ?? 0}</div>
          <div style={{ fontSize: 11, color: '#059669' }}>مقبول: {m.offers_accepted_today ?? 0} | منتهي: {m.offers_expired_today ?? 0}</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #0EA5E9' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>أحداث Socket.IO اللحظية</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#1E293B' }}>{m.realtime_events_today ?? 0}</div>
          <div style={{ fontSize: 11, color: '#0EA5E9' }}>عبر قناة tamreedy:events</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #10B981' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>محاولات FCM Push</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: '#1E293B' }}>{m.push_attempts_today ?? 0}</div>
          <div style={{ fontSize: 11, color: '#059669' }}>ناجحة: {m.push_sent_today ?? 0}</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #F43F5E' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>أخطاء الإشعارات Push</div>
          <div style={{ fontSize: 24, fontWeight: 800, color: m.push_failed_today > 0 ? '#DC2626' : '#64748B' }}>
            {m.push_failed_today ?? 0}
          </div>
          <div style={{ fontSize: 11, color: '#64748B' }}>معاد محاولتها تلقائياً</div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #10B981' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>حالة محرك Dispatch Worker</div>
          <div style={{ fontSize: 18, fontWeight: 800, color: '#059669', marginTop: 4 }}>
            {worker.status === 'RUNNING' ? '🟢 يعمل بشكل طبيعي' : '🔴 متوقف'}
          </div>
          <div style={{ fontSize: 11, color: '#64748B' }}>
            آخر تشغيل: {worker.lastDispatchAt ? new Date(worker.lastDispatchAt).toLocaleTimeString('ar-SY') : 'الآن'}
          </div>
        </div>

        <div className="card" style={{ padding: 14, borderRight: '4px solid #F59E0B' }}>
          <div style={{ fontSize: 12, color: '#64748B' }}>حالة خدمة Firebase FCM</div>
          <div style={{ fontSize: 18, fontWeight: 800, color: fcmHealth?.status === 'FCM_READY' ? '#059669' : '#D97706', marginTop: 4 }}>
            {fcmHealth?.status === 'FCM_READY' ? '🟢 FCM READY' : '🟡 Push معطل (REST نشط)'}
          </div>
          <div style={{ fontSize: 11, color: '#64748B' }}>
            أجهزة مسجلة: {tokenTotal}
          </div>
        </div>
      </div>

      {/* Diagnostic Logs Table */}
      <Panel title="سجل جولات التوزيع وأسباب استبعاد الممرضين (Live Telemetry Breakdown)">
        {logs.length === 0 ? (
          <p style={{ textAlign: 'center', color: '#64748B', padding: 24 }}>لا توجد جولات توزيع مسجلة بعد.</p>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>وقت الجولة</th>
                  <th>رقم الطلب</th>
                  <th>الخدمة المطلوبة</th>
                  <th>رقم الموجة</th>
                  <th>نطاق البحث</th>
                  <th>المؤهلون</th>
                  <th>العروض</th>
                  <th>أسباب الاستبعاد (Exclusion Breakdown)</th>
                  <th>فحص</th>
                </tr>
              </thead>
              <tbody>
                {logs.map((log: any) => {
                  const reasons = log.exclusion_reasons || {};
                  const reasonBadges = Object.entries(reasons).map(([k, v]) => `${k} (${v})`);
                  return (
                    <tr key={log.id}>
                      <td style={{ whiteSpace: 'nowrap', fontSize: 12 }}>
                        {new Date(log.created_at).toLocaleTimeString('ar-SY')}
                      </td>
                      <td style={{ fontFamily: 'monospace', fontSize: 12 }}>
                        {log.request_id.slice(0, 8)}...
                      </td>
                      <td>{log.service_title}</td>
                      <td>
                        <span className="chip chip-default">موجة {log.wave_no}</span>
                      </td>
                      <td>{log.radius_m / 1000} كم</td>
                      <td>
                        <strong style={{ color: log.candidates_found > 0 ? '#059669' : '#DC2626' }}>
                          {log.candidates_found}
                        </strong>
                      </td>
                      <td>
                        <strong style={{ color: log.offers_created > 0 ? '#059669' : '#64748B' }}>
                          {log.offers_created}
                        </strong>
                      </td>
                      <td>
                        {reasonBadges.length === 0 ? (
                          <span style={{ color: '#059669', fontSize: 12 }}>لا توجد استبعادات في هذه الموجة</span>
                        ) : (
                          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
                            {reasonBadges.map((b, idx) => (
                              <span key={idx} style={{
                                fontSize: 11,
                                background: '#FEE2E2',
                                color: '#991B1B',
                                padding: '2px 6px',
                                borderRadius: 4,
                                fontWeight: 600,
                              }}>
                                {b}
                              </span>
                            ))}
                          </div>
                        )}
                      </td>
                      <td>
                        <button
                          className="btn btn-secondary"
                          style={{ padding: '3px 8px', fontSize: 11 }}
                          onClick={() => inspectRequest(log.request_id)}
                        >
                          تفاصيل
                        </button>
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      {/* Request Inspection Modal / Drawer */}
      {selectedRequestId && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(0,0,0,0.5)',
          display: 'flex',
          justifyContent: 'center',
          alignItems: 'center',
          zIndex: 9999,
          padding: 20,
        }}>
          <div style={{
            background: '#FFF',
            borderRadius: 16,
            maxWidth: 900,
            width: '100%',
            maxHeight: '90vh',
            overflowY: 'auto',
            padding: 24,
            boxShadow: '0 20px 25px -5px rgba(0, 0, 0, 0.2)',
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', borderBottom: '1px solid #E2E8F0', paddingBottom: 14, marginBottom: 16 }}>
              <div>
                <h3 style={{ margin: 0, fontSize: 18, color: '#1E293B' }}>
                  فحص تشخيص الطلب: <span style={{ fontFamily: 'monospace' }}>{selectedRequestId}</span>
                </h3>
                <div style={{ fontSize: 12, color: '#64748B', marginTop: 4 }}>
                  حالة التنفيذ والمطابقة وتدفق الإشعارات لهذا الطلب
                </div>
              </div>
              <button
                className="btn btn-secondary"
                style={{ padding: '4px 12px', fontSize: 13 }}
                onClick={() => { setSelectedRequestId(null); setRequestDetail(null); }}
              >
                ✕ إغلاق
              </button>
            </div>

            {detailLoading || !requestDetail ? (
              <p style={{ textAlign: 'center', padding: 40, color: '#64748B' }}>جاري تحميل سجلات التشخيص...</p>
            ) : (
              <div>
                {/* Request Overview */}
                <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 12, marginBottom: 16, background: '#F8FAFC', padding: 14, borderRadius: 12 }}>
                  <div>
                    <span style={{ fontSize: 11, color: '#64748B' }}>الخدمة:</span>
                    <div style={{ fontWeight: 700 }}>{requestDetail.request.service_title}</div>
                  </div>
                  <div>
                    <span style={{ fontSize: 11, color: '#64748B' }}>الحالة الحالية:</span>
                    <div><span className="chip chip-success">{requestDetail.request.status}</span></div>
                  </div>
                  <div>
                    <span style={{ fontSize: 11, color: '#64748B' }}>الموقع / العنوان:</span>
                    <div style={{ fontWeight: 600 }}>{requestDetail.request.address_text || '—'}</div>
                  </div>
                  <div>
                    <span style={{ fontSize: 11, color: '#64748B' }}>تاريخ الإنشاء:</span>
                    <div style={{ fontSize: 12 }}>{new Date(requestDetail.request.created_at).toLocaleString('ar-SY')}</div>
                  </div>
                </div>

                {/* Waves & Candidates Diagnostic Breakdown */}
                <h4 style={{ margin: '16px 0 8px', color: '#1E293B' }}>جولات التوزيع ونتائج فحص الممرضين</h4>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>الموجة</th>
                        <th>نطاق البحث</th>
                        <th>المؤهلون</th>
                        <th>العروض</th>
                        <th>أسباب الاستبعاد بالتفصيل</th>
                      </tr>
                    </thead>
                    <tbody>
                      {requestDetail.diagnostics.map((d: any) => (
                        <tr key={d.id}>
                          <td>موجة {d.wave_no}</td>
                          <td>{d.radius_m} متر</td>
                          <td><strong>{d.candidates_found}</strong></td>
                          <td><strong>{d.offers_created}</strong></td>
                          <td>
                            <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
                              {Object.entries(d.exclusion_reasons || {}).map(([r, c]: any) => (
                                <span key={r} style={{ fontSize: 11, color: '#991B1B' }}>
                                  • {r}: <strong>{c}</strong> ممرض مستبعد
                                </span>
                              ))}
                              {d.excluded_nurses?.map((n: any, idx: number) => (
                                <span key={idx} style={{ fontSize: 10, color: '#64748B' }}>
                                  └ {n.nurse_code}: {n.reason} ({n.detail})
                                </span>
                              ))}
                            </div>
                          </td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>

                {/* Offers Generated */}
                <h4 style={{ margin: '20px 0 8px', color: '#1E293B' }}>العروض المرسلة للممرضين</h4>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>معرف العرض</th>
                        <th>الموجة</th>
                        <th>اسم الممرض</th>
                        <th>الحالة</th>
                        <th>أُرسل في</th>
                        <th>صلاحية العرض</th>
                      </tr>
                    </thead>
                    <tbody>
                      {requestDetail.offers.length === 0 ? (
                        <tr><td colSpan={6} style={{ textAlign: 'center', color: '#64748B' }}>لم يُرسل أي عرض لهذا الطلب بعد</td></tr>
                      ) : (
                        requestDetail.offers.map((o: any) => (
                          <tr key={o.id}>
                            <td style={{ fontFamily: 'monospace', fontSize: 11 }}>{o.id.slice(0, 8)}...</td>
                            <td>موجة {o.wave_no}</td>
                            <td>{o.nurse_name} ({o.nurse_phone})</td>
                            <td><span className={`chip ${o.status === 'ACCEPTED' ? 'chip-success' : o.status === 'EXPIRED' ? 'chip-default' : 'chip-warn'}`}>{o.status}</span></td>
                            <td>{new Date(o.created_at).toLocaleTimeString('ar-SY')}</td>
                            <td>{new Date(o.expires_at).toLocaleTimeString('ar-SY')}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>

                {/* Notification Deliveries Ledger */}
                <h4 style={{ margin: '20px 0 8px', color: '#1E293B' }}>سجل تسليم الإشعارات (FCM Delivery Ledger)</h4>
                <div className="table-wrap">
                  <table>
                    <thead>
                      <tr>
                        <th>القناة</th>
                        <th>المستلم</th>
                        <th>حالة التسليم</th>
                        <th>المحاولات</th>
                        <th>رمز الخطأ</th>
                        <th>التفاصيل</th>
                        <th>الوقت</th>
                      </tr>
                    </thead>
                    <tbody>
                      {requestDetail.deliveries.length === 0 ? (
                        <tr><td colSpan={7} style={{ textAlign: 'center', color: '#64748B' }}>لا توجد محاولات إشعار مسجلة في السجل</td></tr>
                      ) : (
                        requestDetail.deliveries.map((dlv: any) => (
                          <tr key={dlv.id}>
                            <td><span className="chip chip-default">{dlv.channel}</span></td>
                            <td>{dlv.recipient_name}</td>
                            <td>
                              <span className={`chip ${dlv.status === 'SENT' ? 'chip-success' : dlv.status === 'FAILED' ? 'chip-danger' : 'chip-warn'}`}>
                                {dlv.status}
                              </span>
                            </td>
                            <td>{dlv.attempts}</td>
                            <td style={{ fontFamily: 'monospace', fontSize: 11, color: '#DC2626' }}>{dlv.last_error_code || '—'}</td>
                            <td style={{ fontSize: 11, color: '#64748B' }}>{dlv.last_error_detail || '—'}</td>
                            <td style={{ fontSize: 11 }}>{new Date(dlv.created_at).toLocaleTimeString('ar-SY')}</td>
                          </tr>
                        ))
                      )}
                    </tbody>
                  </table>
                </div>
              </div>
            )}
          </div>
        </div>
      )}
    </div>
  );
}
