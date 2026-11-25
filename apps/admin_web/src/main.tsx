import {ToastHost, toast} from './toast';
import React, {useCallback, useEffect, useRef, useState} from 'react';
import {createRoot} from 'react-dom/client';
import {Bell, KeyRound, LogOut, RefreshCw, ChevronLeft, ShieldCheck, CheckCircle2, Sun, Moon, Search, Globe} from 'lucide-react';
import './style.css';
import {Icon} from './ui';
import {Modal} from './widgets';
import {apiBase, getJson, login, logout, restore, sendJson, setLogoutHandler, startIdleWatch} from './session';
import {Promos, ServicesPrices, TopNurses} from './pages_business';
import {Dues, FeesSettings} from './pages_fees';
import {Marketing} from './pages_marketing';
import {Accounts, Credentials, Nurses} from './pages_people';
import {Applications} from './pages_applications';
import {AuditLog, Regions, SettingsPage} from './pages_settings';
import {Dashboard, Finance, Live, LiveMap, Metrics, Page, Reports, RequestRow, Requests, Reviews, WalletRec} from './pages';
import {VisitRisk} from './pages_visit_risk';
import {NightPolicy} from './pages_night_policy';
import {SafetyEvidence} from './pages_safety_evidence';
import {SafetyOperations} from './pages_safety_operations';
import {SafetyDirectory} from './pages_safety_directory';
import {DispatchMonitor} from './pages_dispatch';
import {CancellationAppeals} from './pages_appeals';
import {AppointmentsSchedule} from './pages_schedule';
import {SupportReports, LedgerAudit, BITelemetry, BookingMarketplaceAdmin} from './pages_expansion';

export type NavItem = {
  id: string;
  label: string;
  icon: string;
  title: string;
  desc: string;
  badge?: (extra: Record<string, any>) => number | null;
};

export type NavCategory = {
  title: string;
  items: NavItem[];
};

export const navCategories: NavCategory[] = [
  {
    title: 'غرفة العمليات المباشرة',
    items: [
      {id: 'dashboard', label: 'لوحة التحكم', icon: 'home', title: 'لوحة التحكم الرئيسية', desc: 'نظرة تشغيلية شاملة ومؤشرات حية'},
      {id: 'dispatch', label: 'مراقبة التوزيع', icon: 'bell', title: 'مراقبة الطلبات والإشعارات — Dispatch Monitor', desc: 'تتبع لحظي لمحرك المطابقة الجغرافية وأسباب الاستبعاد وصحة الإشعارات'},
      {id: 'safety-evidence', label: 'الأدلة والحفظ', icon: 'doc', title: 'الأدلة والحفظ القانوني', desc: 'موافقات التصدير وحماية بيانات البلاغات'},
      {id: 'safety-operations', label: 'مركز السلامة', icon: 'bell', title: 'مركز عمليات السلامة', desc: 'استلام البلاغات ومتابعتها وتصعيدها'},
      {id: 'visit-risk', label: 'مراجعة السلامة', icon: 'bell', title: 'مراجعة مخاطر الزيارات', desc: 'مراجعة الزيارات وترشيح المرافقين المهنيين'},
      {id: 'night-policy', label: 'سياسة العمل الليلي', icon: 'bell', title: 'سياسة العمل الليلي', desc: 'ضوابط الأهلية والتغطية بحسب الفترة والمنطقة والخدمة'},
      {id: 'safety-directory', label: 'دليل الطوارئ', icon: 'bell', title: 'دليل الطوارئ', desc: 'إدارة الأرقام الموثقة للاتصال في حالات الطوارئ'},
      {id: 'map', label: 'مراقبة ميدانية', icon: 'pin', title: 'المراقبة الميدانية المباشرة', desc: 'عرض توزيع الحالات والزيارات والممرضين'},
      {id: 'requests', label: 'إدارة الطلبات', icon: 'doc', title: 'إدارة ومتابعة الطلبات', desc: 'تصفية وبحث ومراقبة مراحل الإسناد والخدمة'},
      {id: 'appointments', label: 'الزيارات المجدولة', icon: 'doc', title: 'الزيارات المجدولة وخطط الرعاية', desc: 'إدارة الزيارات المسبقة وخطط الرعاية الدورية'},
      {id: 'marketplace', label: 'السوق المفتوح', icon: 'cart', title: 'سوق الطلبات المفتوح واستعادة الطلبات', desc: 'متابعة الطلبات المفتوحة، عروض الممرضين، إعدادات الاستعادة الذكية، والتحليلات'},
      {id: 'appeals', label: 'الاعتراضات', icon: 'doc', title: 'اعتراضات الإلغاء', desc: 'مراجعة الاعتراضات واتخاذ القرارات'},
    ],
  },
  {
    title: 'الكادر والاعتماد المهني',
    items: [
      {
        id: 'applications',
        label: 'طلبات الانضمام',
        icon: 'plus',
        title: 'طلبات انضمام الممرضين الجدد',
        desc: 'مراجعة الهوية والتراخيص ومواعيد المقابلات الشخصية',
        badge: extra => (extra.pending?.items?.length ? extra.pending.items.length : null),
      },
      {id: 'nurses', label: 'دليل الممرضين', icon: 'users', title: 'دليل الكوادر التمريضية', desc: 'بيانات الممرضين، المهارات، والمستندات الثبوتية'},
      {id: 'credentials', label: 'اعتماد التراخيص', icon: 'check', title: 'اعتماد الصلاحيات والتراخيص', desc: 'تدقيق المستندات الطبية واعتماد سريان المهنة'},
      {id: 'top', label: 'المتميزون والمكافآت', icon: 'heart', title: 'الكادر التمريضي المتميز', desc: 'أفضل الممرضين تقييماً ومكافآت الأداء'},
      {id: 'accounts', label: 'إدارة الحسابات', icon: 'user', title: 'إدارة المستخدمين والحسابات', desc: 'سجلات المرضى والممرضين والحسابات الإدارية'},
    ],
  },
  {
    title: 'الإدارة المالية والخدمات',
    items: [
      {id: 'finance', label: 'الملخص المالي', icon: 'wallet', title: 'التقارير المالية والعمولات', desc: 'إجمالي الزيارات الشهرية وعمولات المنصة'},
      {id: 'prices', label: 'الخدمات والتسعير', icon: 'cash', title: 'كتالوج الخدمات والأسعار', desc: 'إدارة قائمة الخدمات وأسعارها اللحظية في التطبيقات'},
      {id: 'fees', label: 'الرسوم والضرائب', icon: 'settings', title: 'إعدادات الرسوم والتعرفة', desc: 'بدل المسافة، الساعات الليلية، العطلات، والضرائب'},
      {id: 'dues', label: 'مستحقات الشركة', icon: 'wallet', title: 'مستحقات الشركة من الممرضين', desc: 'تسوية المبالغ النقدية المقبوضة ميدانياً'},
      {id: 'wallet', label: 'المحافظ والتسويات', icon: 'wallet', title: 'مطابقة المحافظ والتسويات', desc: 'تنظيم آلية الدفع النقدي ومطابقة الحسابات'},
      {id: 'ledger-audit', label: 'دفتر الأستاذ', icon: 'wallet', title: 'دفتر الأستاذ والقيود المزدوجة', desc: 'تدقيق القيود المحاسبية وتوازن الحسابات'},
    ],
  },
  {
    title: 'النمو والتسويق والجودة',
    items: [
      {id: 'marketing', label: 'أدوات التسويق', icon: 'heart', title: 'الحملات والأدوات الترويجية', desc: 'عروض الأوقات الهادئة، برامج الولاء، واستعادة المرضى'},
      {id: 'packs', label: 'الباقات العلاجية', icon: 'cart', title: 'إدارة الباقات والاشتراكات', desc: 'تصميم وتفعيل الباقات الصحية المنزلية'},
      {id: 'promos', label: 'أكواد الخصم', icon: 'star', title: 'إدارة أكواد وكوبونات الخصم', desc: 'إنشاء ومتابعة فاعلية الأكواد الترويجية'},
      {
        id: 'reviews',
        label: 'الجودة والشكاوى',
        icon: 'alert',
        title: 'التقييمات وبلاغات السلامة',
        desc: 'متابعة جودة الرعاية وبلاغات السلامة الطبية',
        badge: extra => (extra.reviews?.safety_reports ? extra.reviews.safety_reports : null),
      },
      {id: 'support-reports', label: 'مركز الشكاوى', icon: 'alert', title: 'مركز الشكاوى وبلاغات الجودة', desc: 'فرز ومعالجة الشكاوى وبلاغات المستخدمين'},
      {id: 'bi-telemetry', label: 'مؤشرات النمو (BI)', icon: 'chart', title: 'تحليلات ونمو الأعمال', desc: 'معدلات الإيفاء، الإيرادات، ومؤشرات ولاء المرضى'},
    ],
  },
  {
    title: 'التقارير والنظام',
    items: [
      {id: 'reports', label: 'التقارير والتصدير', icon: 'chart', title: 'التقارير التحليلية وتصدير البيانات', desc: 'استخراج تقارير Excel/CSV ومؤشرات الأداء'},
      {id: 'regions', label: 'المناطق الجغرافية', icon: 'pin', title: 'المناطق ونطاقات الخدمة', desc: 'إدارة المحافظات ومناطق التغطية الجغرافية'},
      {id: 'audit', label: 'سجل التدقيق', icon: 'lock', title: 'سجل تدقيق العمليات الحساسة', desc: 'التتبع الأمني: من أجرى التعديل، التفاصيل، والوقت'},
      {id: 'settings', label: 'إعدادات المنظومة', icon: 'settings', title: 'إعدادات النظام العامة', desc: 'المناطق الجغرافية، موجات التوزيع، وبيانات الشركة'},
    ],
  },
];

// Flat lookup map
const allItems = navCategories.flatMap(c => c.items);
const findNavItem = (id: string) => allItems.find(x => x.id === id) ?? allItems[0];
const findNavCategory = (id: string) => navCategories.find(c => c.items.some(i => i.id === id))?.title ?? '';

/** Nothing of the dashboard is rendered before a valid admin session exists. */
function LoginScreen({onDone}: {onDone: () => void}) {
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError('');
    setBusy(true);
    try {
      await login(phone.trim(), password);
      setPassword('');
      onDone();
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login-wrap">
      <form className="login-card" onSubmit={e => void submit(e)} autoComplete="on">
        <div className="login-brand">
          <img src="/logo.png" alt="تمريضي" />
          <h2>لوحة إدارة العمليات</h2>
          <p>أهلاً بك مجدداً. سجّل الدخول لإدارة المنصة</p>
        </div>
        <label>
          رقم الهاتف المعتمد
          <input
            name="username"
            autoComplete="username"
            dir="ltr"
            inputMode="tel"
            value={phone}
            onChange={e => setPhone(e.target.value)}
            placeholder="+9639..."
            autoFocus
          />
        </label>
        <label>
          كلمة المرور
          <input
            name="password"
            autoComplete="current-password"
            type="password"
            dir="ltr"
            value={password}
            onChange={e => setPassword(e.target.value)}
          />
        </label>
        {error && <div className="error" role="alert">{error}</div>}
        <button className="pill on login-btn" disabled={busy || !phone || password.length < 6}>
          {busy ? 'جارٍ التحقق...' : 'تسجيل الدخول'}
        </button>
        <small>الدخول مخصص للمشرفين والكوادر الإدارية المصرّح لها. تُسجَّل جميع الحركات.</small>
      </form>
    </div>
  );
}

function ChangePassword({onClose, forced = false}: {onClose: () => void; forced?: boolean}) {
  const [f, setF] = useState({current: '', next: '', again: ''});
  const [msg, setMsg] = useState('');

  async function save() {
    setMsg('');
    if (f.next.length < 12) return setMsg('كلمة المرور الجديدة يجب أن تكون 12 حرفاً على الأقل');
    if (f.next !== f.again) return setMsg('تأكيد كلمة المرور غير متطابق');
    try {
      await sendJson('POST', '/v1/auth/change-password', {currentPassword: f.current, newPassword: f.next});
      await logout(true);
      toast.ok('تم تحديث كلمة المرور بنجاح. يُرجى تسجيل الدخول مجدداً.');
    } catch (e) {
      setMsg((e as Error).message);
    }
  }

  return (
    <Modal
      title={forced ? 'يجب تغيير كلمة المرور للمتابعة' : 'تغيير كلمة المرور'}
      onClose={forced ? () => {} : onClose}
      maxWidth="480px"
    >
      <div className="form one">
        <label>
          كلمة المرور الحالية
          <input type="password" dir="ltr" value={f.current} onChange={e => setF({...f, current: e.target.value})} />
        </label>
        <label>
          كلمة المرور الجديدة (12 حرفاً على الأقل)
          <input type="password" dir="ltr" value={f.next} onChange={e => setF({...f, next: e.target.value})} />
        </label>
        <label>
          تأكيد كلمة المرور الجديدة
          <input type="password" dir="ltr" value={f.again} onChange={e => setF({...f, again: e.target.value})} />
        </label>
      </div>
      {msg && <p className="hint err">{msg}</p>}
      <div className="actions">
        <button className="pill on" onClick={() => void save()}>حفظ التغيير</button>
        {forced ? (
          <button className="pill" onClick={() => void logout()}>تسجيل الخروج</button>
        ) : (
          <button className="pill" onClick={onClose}>إلغاء</button>
        )}
      </div>
    </Modal>
  );
}

function App() {
  const [active, setActive] = useState<string>('dashboard');
  const [theme, setTheme] = useState<'light' | 'dark'>(() => (localStorage.getItem('tam_theme') === 'dark' ? 'dark' : 'light'));
  const [dir, setDir] = useState<'rtl' | 'ltr'>(() => (localStorage.getItem('tam_dir') === 'ltr' ? 'ltr' : 'rtl'));
  const [cmdQuery, setCmdQuery] = useState('');
  const cmdInputRef = useRef<HTMLInputElement>(null);
  const [me, setMe] = useState<any>(null);

  useEffect(() => {
    const onKeyDown = (e: KeyboardEvent) => {
      if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') {
        e.preventDefault();
        cmdInputRef.current?.focus();
      } else if (e.key === 'Escape' && cmdQuery) {
        setCmdQuery('');
        cmdInputRef.current?.blur();
      }
    };
    window.addEventListener('keydown', onKeyDown);
    return () => window.removeEventListener('keydown', onKeyDown);
  }, [cmdQuery]);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
    localStorage.setItem('tam_theme', theme);
  }, [theme]);

  useEffect(() => {
    document.documentElement.setAttribute('dir', dir);
    document.documentElement.setAttribute('lang', dir === 'rtl' ? 'ar' : 'en');
    localStorage.setItem('tam_dir', dir);
  }, [dir]);
  const [metrics, setMetrics] = useState<Metrics | null>(null);
  const [requests, setRequests] = useState<RequestRow[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [more, setMore] = useState(false);
  const [extra, setExtra] = useState<Record<string, any>>({});
  const [error, setError] = useState('');
  const [pw, setPw] = useState(false);
  const [mustChange, setMustChange] = useState(false);
  const [tick, setTick] = useState(0);
  const [refreshing, setRefreshing] = useState(false);
  const idle = useRef<(() => void) | undefined>(undefined);

  const reload = useCallback(async () => {
    try {
      setRefreshing(true);
      const who = await getJson('/v1/auth/me');
      setMe(who);
      if (who.mustChangePassword) {
        setMustChange(true);
        return;
      }
      setMustChange(false);
      if (who.role === 'CLINICAL_REVIEWER') {
        const pending = await getJson('/v1/admin/credentials/pending').catch(() => undefined);
        setExtra({pending});
        setError('');
        setTick(t => t + 1);
        return;
      }
      const [m, r] = await Promise.all([getJson('/v1/admin/dashboard'), getJson('/v1/admin/requests')]);
      const paths: Record<string, string> = {
        live: 'live',
        extras: 'dashboard/extras',
        pending: 'credentials/pending',
        finance: 'finance/summary',
        settlements: 'finance/settlements',
        reviews: 'reviews/summary',
        settings: 'system-settings',
      };
      const got: Record<string, any> = {};
      await Promise.all(
        Object.entries(paths).map(async ([k, p]) => {
          try {
            got[k] = await getJson(`/v1/admin/${p}`);
          } catch {
            /* optional panel */
          }
        }),
      );
      const page = r as Page<RequestRow>;
      setExtra(got);
      setMetrics(m);
      setRequests(page.items);
      setCursor(page.nextCursor);
      setError('');
      setTick(t => t + 1);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setRefreshing(false);
    }
  }, []);

  useEffect(() => {
    void reload();
  }, [reload]);

  // Idle logout
  const idleMin = Number(extra.settings?.settings?.security?.idleMinutes ?? 20);
  useEffect(() => {
    idle.current?.();
    idle.current = startIdleWatch(idleMin);
    return () => idle.current?.();
  }, [idleMin]);

  // Auto-refresh operational numbers
  useEffect(() => {
    const t = window.setInterval(() => void reload(), 60_000);
    return () => window.clearInterval(t);
  }, [reload]);

  async function loadMore() {
    if (!cursor || more) return;
    setMore(true);
    try {
      const page = (await getJson(`/v1/admin/requests?limit=20&cursor=${encodeURIComponent(cursor)}`)) as Page<RequestRow>;
      setRequests(p => [...p, ...page.items]);
      setCursor(page.nextCursor);
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setMore(false);
    }
  }

  const live: Live = {
    get: getJson,
    token: String(tick),
    apiBase,
    extra,
    metrics,
    requests,
    hasMore: !!cursor,
    loadMore: () => void loadMore(),
    more,
    reload,
    navigate: (id: string) => setActive(id),
  };

  const cur = findNavItem(active);
  const curCategory = findNavCategory(active);

  const body: Record<string, React.ReactNode> = {
    dashboard: <Dashboard live={live} />,
    dispatch: <DispatchMonitor live={live} />,
    'visit-risk': <VisitRisk />,
    'night-policy': <NightPolicy />,
    'safety-evidence': <SafetyEvidence />,
    'safety-operations': <SafetyOperations />,
    'safety-directory': <SafetyDirectory />,
    map: <LiveMap live={live} />,
    requests: <Requests live={live} />,
    appeals: <CancellationAppeals live={live} />,
    appointments: <AppointmentsSchedule live={live} />,
    marketplace: <BookingMarketplaceAdmin live={live} />,
    applications: <Applications live={live} />,
    nurses: <Nurses live={live} />,
    credentials: <Credentials live={live} />,
    finance: <Finance live={live} />,
    wallet: <WalletRec live={live} />,
    'ledger-audit': <LedgerAudit live={live} />,
    accounts: <Accounts live={live} />,
    prices: <ServicesPrices live={live} />,
    marketing: <Marketing live={live} />,
    packs: <Marketing live={live} />,
    'support-reports': <SupportReports live={live} />,
    'bi-telemetry': <BITelemetry live={live} />,
    fees: <FeesSettings live={live} />,
    dues: <Dues live={live} />,
    promos: <Promos live={live} />,
    top: <TopNurses live={live} />,
    reviews: <Reviews live={live} />,
    reports: <Reports live={live} />,
    audit: <AuditLog live={live} />,
    regions: <Regions />,
    settings: <SettingsPage live={live} />,
  };

  return (
    <div className="shell">
      <aside className="side">
        <div className="side-brand">
          <div className="logo">
            <img src="/logo.png" alt="تمريضي" />
          </div>
          <div className="brand-tag">
            <span>لوحة إدارة العمليات</span>
            <div className="live-dot" title="متصل بالخادم" />
          </div>
        </div>

        <nav className="side-nav">
          {navCategories.map(cat => (
            <div key={cat.title} className="nav-group">
              <span className="nav-group-title">{cat.title}</span>
              <div className="nav-group-items">
                {cat.items.map(item => {
                  const badgeCount = item.badge?.(extra);
                  const isSel = active === item.id;
                  return (
                    <button
                      key={item.id}
                      className={`nav ${isSel ? 'sel' : ''}`}
                      onClick={() => setActive(item.id)}
                    >
                      <Icon name={item.icon} size={18} />
                      <span className="nav-label">{item.label}</span>
                      {badgeCount ? <span className="nav-badge">{badgeCount}</span> : null}
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        <div className="side-foot">
          <div className="server-status">
            <span className="status-indicator" />
            <span>نظام تمريضي — خادم متصل</span>
          </div>
        </div>
      </aside>

      <main>
        <header>
          <div className="header-meta">
            <div className="breadcrumbs">
              <span>{curCategory}</span>
              <ChevronLeft size={14} />
              <span className="cur-crumb">{cur.label}</span>
            </div>
            <h1>{cur.title}</h1>
            <p>{cur.desc}</p>
          </div>

          <div className="header-actions">
            <div className="cmd-search-wrap">
              <input
                ref={cmdInputRef}
                className="cmd-search-input"
                type="search"
                placeholder="بحث سريع في الوحدات... (Ctrl+K)"
                value={cmdQuery}
                onChange={e => setCmdQuery(e.target.value)}
              />
              {cmdQuery.trim() && (
                <div className="cmd-search-dropdown">
                  {allItems
                    .filter(it => it.label.includes(cmdQuery.trim()) || it.title.includes(cmdQuery.trim()))
                    .slice(0, 8)
                    .map(it => (
                      <button
                        key={it.id}
                        className="cmd-search-item"
                        onClick={() => {
                          setActive(it.id);
                          setCmdQuery('');
                        }}
                      >
                        <span>{it.label}</span>
                        <small className="hint">{findNavCategory(it.id)}</small>
                      </button>
                    ))}
                </div>
              )}
            </div>

            <button
              className={`action-btn ${refreshing ? 'rotating' : ''}`}
              title="تحديث البيانات فوراً"
              onClick={() => void reload()}
            >
              <RefreshCw size={17} />
              <span>تحديث</span>
            </button>

            <div className="user-profile">
              <div className="user-info">
                <strong>{me?.display_name ?? 'المشرف العام'}</strong>
                <small dir="ltr">{me?.phone_e164 ?? ''}</small>
              </div>
              <div className="avatar">
                {String(me?.display_name ?? 'م').slice(0, 1)}
              </div>
            </div>

            <div className="header-icons">
              <button
                className="ghost"
                title={theme === 'dark' ? 'الوضع الفاتح' : 'الوضع الداكن'}
                onClick={() => setTheme(t => (t === 'dark' ? 'light' : 'dark'))}
              >
                {theme === 'dark' ? <Sun size={18} /> : <Moon size={18} />}
              </button>
              <button
                className="ghost"
                title={dir === 'rtl' ? 'تبديل إلى LTR' : 'تبديل إلى RTL'}
                onClick={() => setDir(d => (d === 'rtl' ? 'ltr' : 'rtl'))}
              >
                <Globe size={18} />
              </button>
              <button className="ghost" title="تغيير كلمة المرور" onClick={() => setPw(true)}>
                <KeyRound size={18} />
              </button>
              <button className="ghost logout-btn" title="تسجيل الخروج" onClick={() => void logout()}>
                <LogOut size={18} />
              </button>
            </div>
          </div>
        </header>

        {(pw || mustChange) && <ChangePassword forced={mustChange} onClose={() => setPw(false)} />}
        {error && <div className="error">{error}</div>}

        <div className="content">
          {mustChange ? null : body[active]}
        </div>
      </main>
    </div>
  );
}

function Root() {
  const [phase, setPhase] = useState<'boot' | 'out' | 'in'>('boot');
  useEffect(() => {
    setLogoutHandler(() => setPhase('out'));
    void restore().then(ok => setPhase(ok ? 'in' : 'out'));
  }, []);

  if (phase === 'boot') {
    return (
      <div className="login-wrap">
        <div className="loading-card">
          <div className="spinner" />
          <p className="hint">جارٍ تهيئة لوحة التحكم...</p>
        </div>
      </div>
    );
  }

  return (
    <>
      {phase === 'in' ? <App /> : <LoginScreen onDone={() => setPhase('in')} />}
      <ToastHost />
    </>
  );
}

createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <Root />
  </React.StrictMode>,
);
