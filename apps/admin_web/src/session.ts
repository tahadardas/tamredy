import {toast} from './toast';
/** Admin session handling.
 *  - The access token lives ONLY in memory.
 *  - The refresh token lives in sessionStorage (cleared when the tab closes) so a page reload does not force a new login,
 *    and it is rotated on every refresh (the server detects replays).
 *  - Idle timeout: no activity for IDLE_MINUTES -> logout. */
export const apiBase: string = import.meta.env.VITE_API_BASE_URL ?? '/api';
const RT = 'tm_rt';

export interface SessionInfo { accessToken: string; role: string }
let access = '';
let refreshing: Promise<boolean> | null = null;
let onLoggedOut: () => void = () => {};
export const setLogoutHandler = (f: () => void) => { onLoggedOut = f; };
export const currentToken = () => access;

const store = {
  get: () => { try { return sessionStorage.getItem(RT); } catch { return null; } },
  set: (v: string | null) => { try { v ? sessionStorage.setItem(RT, v) : sessionStorage.removeItem(RT); } catch { /* private mode */ } },
};

async function raw(path: string, init: RequestInit = {}, token = access) {
  const headers = new Headers(init.headers);
  if (token) headers.set('Authorization', `Bearer ${token}`);
  if (init.body && !(init.body instanceof FormData) && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
  try { return await fetch(`${apiBase}${path}`, {...init, headers}); }
  catch { throw new Error('تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى'); }
}

export async function login(phone: string, password: string): Promise<void> {
  const r = await raw('/v1/auth/login', {method: 'POST', body: JSON.stringify({phone, password})}, '');
  const d = await r.json().catch(() => ({}));
  if (r.status === 429) throw new Error('الحساب مقفل مؤقتًا بسبب محاولات خاطئة كثيرة. حاول بعد 15 دقيقة.');
  if (!r.ok) throw new Error('بيانات الدخول غير صحيحة');
  if (d.role !== 'ADMIN') throw new Error('هذا الحساب ليس حساب إدارة');
  access = d.accessToken; store.set(d.refreshToken);
}

/** Restores a session after a page reload from the rotating refresh token. */
export async function restore(): Promise<boolean> { return store.get() ? refresh() : false; }

function refresh(): Promise<boolean> {
  refreshing ??= (async () => {
    const rt = store.get();
    if (!rt) return false;
    try {
      const r = await raw('/v1/auth/refresh', {method: 'POST', body: JSON.stringify({refreshToken: rt})}, '');
      if (!r.ok) return false;
      const d = await r.json();
      if (d.role !== 'ADMIN') return false;
      access = d.accessToken; store.set(d.refreshToken);
      return true;
    } catch { return false; } finally { refreshing = null; }
  })();
  return refreshing;
}

export async function logout(silent = false) {
  const rt = store.get();
  access = ''; store.set(null);
  if (rt && !silent) { try { await raw('/v1/auth/logout', {method: 'POST', body: JSON.stringify({refreshToken: rt})}, ''); } catch { /* offline */ } }
  onLoggedOut();
}

/** Authenticated request with one silent refresh on 401. */
export async function api(path: string, init: RequestInit = {}): Promise<Response> {
  let r = await raw(path, init);
  if (r.status === 401 && await refresh()) r = await raw(path, init);
  if (r.status === 401) { await logout(true); throw new Error('انتهت الجلسة، سجّل الدخول من جديد'); }
  return r;
}
export async function getJson(path: string) {
  const r = await api(path);
  if (!r.ok) throw new Error(await errText(r));
  return r.json();
}
export const msgOf = (e: unknown) => e instanceof Error ? e.message : String(e);
export async function sendJson(method: string, path: string, body?: unknown) {
  let r: Response;
  try { r = await api(path, {method, body: body === undefined ? undefined : JSON.stringify(body)}); }
  catch (e) { toast.error(msgOf(e)); throw e; }
  const d = await r.json().catch(() => ({}));
  if (!r.ok) { const m = errorAr(d, r.status); toast.error(m); throw new Error(m); } // always visible, even if the caller forgets to show it
  toast.ok('تمت العملية بنجاح');
  return d;
}
async function errText(r: Response) { const d = await r.json().catch(() => ({})); return errorAr(d, r.status); }

/** Every code the API can return, in plain Arabic. */
const messages: Record<string, string> = {
  // accounts & sessions
  LOGIN_INVALID: 'رقم الهاتف أو كلمة المرور غير صحيحة', ACCOUNT_LOCKED: 'الحساب مقفل مؤقتًا بسبب محاولات خاطئة كثيرة. حاول بعد 15 دقيقة', ACCOUNT_INACTIVE: 'الحساب موقوف أو محذوف',
  REFRESH_EXPIRED: 'انتهت الجلسة، سجّل الدخول من جديد', REFRESH_INVALID: 'انتهت الجلسة، سجّل الدخول من جديد', REFRESH_REUSED: 'أُنهيت الجلسة لأسباب أمنية، سجّل الدخول من جديد',
  AUTH_REQUIRED: 'سجّل الدخول أولًا', INVALID_TOKEN: 'انتهت الجلسة، سجّل الدخول من جديد', PASSWORD_CHANGE_REQUIRED: 'يجب تغيير كلمة المرور أولًا',
  WRONG_PASSWORD: 'كلمة المرور الحالية غير صحيحة', WEAK_PASSWORD: 'كلمة المرور ضعيفة: اجعلها أطول، ولا تكرّر الحالية أو الافتراضية أو رقم الهاتف',
  BAD_DEFAULT_PW: 'كلمة المرور الافتراضية 6 أحرف على الأقل', BAD_IDLE: 'مدة الخمول بين 5 و240 دقيقة', BAD_PWLEN: 'طول كلمة المرور بين 8 و64',
  PHONE_ALREADY_REGISTERED: 'رقم الهاتف مسجّل مسبقًا', NURSE_NO_TAKEN: 'رقم الممرض مستخدم لممرض آخر', CANNOT_CHANGE_OWN_STATUS: 'لا يمكنك تغيير حالة حسابك',
  CANNOT_CHANGE_OWN_ROLE: 'لا يمكنك تغيير صلاحيتك', CANNOT_DELETE_SELF: 'لا يمكنك حذف حسابك', LAST_ADMIN: 'لا يمكن حذف أو إيقاف آخر مدير', INVALID_ROLE: 'نوع الحساب غير صالح',
  ROLE_NOT_ALLOWED: 'ليست لديك صلاحية لهذه العملية', FORBIDDEN: 'ليست لديك صلاحية لهذه العملية', REGISTRATION_CLOSED: 'التسجيل مغلق حاليًا', TOO_MANY_REGISTRATIONS: 'محاولات تسجيل كثيرة، حاول لاحقًا',
  OTP_DISABLED_PASSWORD_MODE: 'الدخول برمز الرسائل غير مفعّل', OTP_INVALID: 'الرمز غير صحيح أو منتهٍ', OTP_RATE_LIMITED: 'محاولات كثيرة، انتظر قليلًا', MFA_REQUIRED: 'مطلوب تحقق إضافي',
  // nurses, documents, licences
  NURSE_ON_ACTIVE_VISIT: 'الممرض في زيارة جارية؛ أنهِها قبل الحذف', DOCUMENT_BACKS_APPROVED_LICENSE: 'المستند أساس رخصة معتمدة ولا يُحذف', LICENSE_FIELDS_TOGETHER: 'رقم الرخصة وتاريخ انتهائها مطلوبان معًا',
  CREDENTIAL_ALREADY_DECIDED: 'سبق اتخاذ قرار في هذه الرخصة (حدّث الصفحة)', LICENSE_EXPIRED: 'الرخصة منتهية الصلاحية فلا يمكن اعتمادها', LICENSE_NOT_VERIFIED: 'رخصة الممرض غير معتمدة بعد',
  REASON_REQUIRED: 'اكتب السبب', TOO_MANY_DOCUMENTS: 'بلغت الحد الأقصى من المستندات', FILE_TOO_LARGE: 'الملف أكبر من 8 ميغابايت', FILE_TYPE_NOT_ALLOWED: 'يُسمح بـPDF وصور JPG/PNG فقط',
  FILE_REQUIRED: 'اختر ملفًا', REGION_INVALID: 'اختر منطقة تابعة للمحافظة المختارة (وفعّالة)', REGION_EXISTS: 'الاسم موجود مسبقًا',
  APPLICATION_ALREADY_OPEN: 'يوجد طلب انضمام مفتوح بهذا الرقم', APPLICATION_ALREADY_DECIDED: 'سبق اتخاذ قرار في هذا الطلب (حدّث الصفحة)',
  // settings & orders
  WAVES_MUST_GROW: 'يجب أن يزداد نصف القطر في كل موجة', BAD_WAVES: 'موجات البحث غير صالحة (من 1 إلى 5 موجات)', BAD_RADIUS: 'نصف القطر بين 500 و50000 متر', BAD_SECONDS: 'مدة الموجة بين 5 و120 ثانية', BAD_LIMIT: 'عدد الممرضين بين 1 و100',
  ORDERS_PAUSED: 'استقبال الطلبات متوقف مؤقتًا', NOTHING_TO_UPDATE: 'لا تغييرات للحفظ', NOT_FOUND: 'العنصر غير موجود أو حُذف (حدّث الصفحة)',
  // services, promos, marketing
  SERVICE_CODE_EXISTS: 'رمز الخدمة مستخدم', CODE_TITLE_PRICE_REQUIRED: 'الرمز والاسم والسعر مطلوبة', PROMO_CODE_EXISTS: 'كود الخصم موجود مسبقًا', CODE_TYPE_VALUE_REQUIRED: 'الكود والنوع والقيمة مطلوبة',
  INVALID_AMOUNT: 'المبلغ غير صالح', INVALID_DATE: 'التاريخ غير صالح', INVALID_DAYS: 'الأيام غير صالحة', INVALID_TIME: 'الوقت غير صالح (HH:MM)', INVALID_PERIOD: 'الفترة غير صالحة', INVALID_NAME: 'الاسم غير صالح',
  INVALID_AUDIENCE: 'الفئة المستهدفة غير صالحة', INVALID_TEMPLATES: 'قوالب الرسائل غير صالحة', INVALID_STATUS: 'الحالة غير صالحة', CONFIG_REQUIRED: 'القيم مطلوبة', BROADCASTS_DISABLED: 'ميزة الرسائل الجماعية غير مفعّلة',
  INVALID_PAGINATION: 'ترقيم الصفحات غير صالح', INVALID_REQUEST: 'الطلب غير صالح', INVALID_STATE_TRANSITION: 'هذه العملية غير مسموحة في الحالة الحالية', REPUTATION_AND_COMMISSION_REQUIRED: 'أدخل حدّ السمعة والعمولة معًا',
  // money
  SETTLEMENT_REQUIRED: 'أدخل بيانات التسوية', ALREADY_PAID: 'سُدّد المبلغ مسبقًا', NOT_BILLED_YET: 'لم تُصدر الفاتورة بعد', NOT_COMPLETED_YET: 'الزيارة لم تكتمل بعد', WALLET_NOT_ENABLED: 'المحفظة غير مفعّلة', TIPS_DISABLED: 'البقشيش غير مفعّل',
  // patients app flows (shown if staff screens ever surface them)
  PROMO_NOT_FOUND: 'كود الخصم غير موجود', PROMO_EXPIRED: 'كود الخصم منتهي', PROMO_INACTIVE: 'كود الخصم غير فعّال', PROMO_EXHAUSTED: 'استُنفد كود الخصم', PROMO_ALREADY_USED: 'استُخدم الكود سابقًا',
  REFERRAL_DISABLED: 'برنامج الإحالة غير مفعّل', ROUTES_NOT_CONFIGURED: 'خدمة الخرائط غير مضبوطة', ROUTES_UPSTREAM_ERROR: 'تعذر الاتصال بخدمة الخرائط',
};
const fields: Record<string, string> = {
  phone: 'الهاتف', displayName: 'الاسم', password: 'كلمة المرور', newPassword: 'كلمة المرور الجديدة', currentPassword: 'كلمة المرور الحالية', nurseNo: 'رقم الممرض', nationalId: 'الرقم الوطني',
  governorateId: 'المحافظة', areaId: 'المنطقة', specialty: 'الاختصاص', notes: 'الملاحظات', expiresAt: 'تاريخ انتهاء الرخصة', licenseRef: 'رقم الرخصة', kind: 'نوع المستند', title: 'العنوان',
  nameAr: 'الاسم', docKind: 'نوع الوثيقة', acceptTerms: 'الإقرار والموافقة', interviewAt: 'موعد المقابلة', lat: 'خط العرض', lng: 'خط الطول', role: 'الصلاحية', status: 'الحالة', serviceIds: 'الخدمات', decision: 'القرار', reason: 'السبب', code: 'الرمز', price: 'السعر', value: 'القيمة',
};
const byStatus: Record<number, string> = {
  400: 'البيانات المدخلة غير صالحة', 401: 'انتهت الجلسة، سجّل الدخول من جديد', 403: 'ليست لديك صلاحية لهذه العملية', 404: 'العنصر أو الخدمة غير موجودة على الخادم (قد يحتاج الخادم إلى تحديث)',
  409: 'تعارض: العملية لا تتوافق مع الحالة الحالية، حدّث الصفحة وأعد المحاولة', 413: 'الملف كبير جدًا', 422: 'بيانات غير قابلة للمعالجة، تحقق من صحة المدخلات', 429: 'محاولات كثيرة، انتظر قليلًا ثم أعد المحاولة', 500: 'خطأ داخلي في الخادم، حاول لاحقًا وأبلغ المسؤول إن تكرر',
  502: 'الخادم غير متاح حاليًا', 503: 'الخدمة غير متاحة مؤقتًا', 504: 'انتهت مهلة الخادم، حاول لاحقًا',
};
export function errorAr(d: any, status: number) {
  const code = typeof d?.code === 'string' ? d.code : undefined;
  if (code && messages[code]) return messages[code]!;
  // class-validator messages ("phone must match ...") -> name the offending fields in Arabic
  if (Array.isArray(d?.message)) {
    const names = [...new Set(d.message.map((m: string) => fields[String(m).split(' ')[0] ?? ''] ?? null).filter(Boolean))];
    return names.length ? `تحقق من الحقول: ${names.join('، ')}` : byStatus[400]!;
  }
  const msg = typeof d?.message === 'string' ? d.message : '';
  if (/^Cannot (GET|POST|PUT|PATCH|DELETE)/.test(msg)) return byStatus[404]!;
  return byStatus[status] ?? (status >= 500 ? byStatus[500]! : `تعذر تنفيذ العملية (رمز ${status})`);
}

export async function checkServerConnection(): Promise<boolean> {
  try {
    const r = await fetch(`${apiBase}/health`, { method: 'GET', signal: AbortSignal.timeout(5000) });
    return r.ok;
  } catch {
    return false;
  }
}

/** Idle logout: any user activity resets the timer. */
export function startIdleWatch(minutes: number): () => void {
  let t: number;
  const reset = () => { window.clearTimeout(t); t = window.setTimeout(() => void logout(), minutes * 60_000); };
  const ev = ['mousemove', 'keydown', 'click', 'touchstart', 'scroll'];
  ev.forEach(e => window.addEventListener(e, reset, {passive: true}));
  reset();
  return () => { window.clearTimeout(t); ev.forEach(e => window.removeEventListener(e, reset)); };
}
