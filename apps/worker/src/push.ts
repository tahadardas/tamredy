import { createPrivateKey, randomUUID } from 'node:crypto';
import { callIsRinging } from './call-delivery.ts';
import jwt from 'jsonwebtoken';

export type RecipientRole = 'PATIENT' | 'NURSE' | 'ADMIN' | 'CLINICAL_REVIEWER';
export type TargetApp = 'PATIENT_APP' | 'NURSE_APP' | 'ADMIN_WEB';

export function targetAppForRole(role?: string): TargetApp | undefined {
  if (role === 'NURSE') return 'NURSE_APP';
  if (role === 'PATIENT') return 'PATIENT_APP';
  if (role === 'ADMIN' || role === 'CLINICAL_REVIEWER') return 'ADMIN_WEB';
  return undefined;
}

export function deepLinkForPush(
  type: string,
  role: string | undefined,
  payload: Record<string, any> = {},
): string {
  const prefix = role === 'NURSE' ? 'tamreedy://nurse' : 'tamreedy://patient';
  const reqId = payload.requestId ? String(payload.requestId) : '';
  const asgnId = payload.assignmentId ? String(payload.assignmentId) : '';
  const offerId = payload.offerId ? String(payload.offerId) : '';
  const callId = payload.callId ? String(payload.callId) : '';
  const convId = payload.conversationId ? String(payload.conversationId) : '';

  if (type === 'call.incoming' && callId) return `${prefix}/calls/${callId}`;
  if (type === 'chat.message' && convId) return `${prefix}/chat/${convId}`;
  if (role === 'NURSE') {
    if (type === 'offer.created' && offerId) return `${prefix}/offers/${offerId}`;
    if (type.startsWith('marketplace.recovery')) return `${prefix}/marketplace`;
    if (type === 'marketplace.proposal.accepted' || type === 'visit.departure_delayed') {
      return asgnId ? `${prefix}/assignments/${asgnId}` : `${prefix}/home`;
    }
    if (type === 'payment.tip' && reqId) return `${prefix}/requests/${reqId}/bill`;
    if (type.startsWith('safety.')) return `${prefix}/guardian`;
    return reqId ? `${prefix}/requests/${reqId}` : `${prefix}/home`;
  }
  if (type === 'marketplace.proposal.created' || type === 'marketplace.proposal.withdrawn') {
    return reqId ? `${prefix}/requests/${reqId}/proposals` : `${prefix}/requests`;
  }
  if (type === 'visit.complete' || type.startsWith('payment.')) {
    return reqId ? `${prefix}/requests/${reqId}/bill` : `${prefix}/requests`;
  }
  return reqId ? `${prefix}/requests/${reqId}` : `${prefix}/home`;
}

/**
 * Role-aware push copy per outbox event type.
 * Messages never contain names, addresses or medical details: the app fetches details over REST after opening.
 */
export function pushCopy(
  type: string,
  payload: Record<string, any> = {},
  role?: string,
): { title: string; body: string } | null {
  const effectiveRole = role ?? payload.recipientRole;

  switch (type) {
    case 'winback.offer':
      return { title: 'اشتقنا لك 💙', body: `خصم ${payload.percent ?? ''}% على طلبك القادم — صالح لفترة محدودة.` };
    case 'pack.granted':
      return { title: 'تم تفعيل باقتك', body: 'خصم باقتك يُطبَّق تلقائيًا على زياراتك القادمة.' };
    case 'offer.closed':
    case 'offer.expired':
      return effectiveRole === 'PATIENT'
        ? null
        : { title: 'أُغلق العرض', body: 'تم إسناد الطلب أو انتهت مهلة هذا العرض.' };
    case 'visit.interrupted':
      return effectiveRole === 'NURSE'
        ? { title: 'تم إيقاف الزيارة', body: 'راجع مركز الأمان وحالة الزيارة في التطبيق.' }
        : { title: 'توقفت الزيارة', body: 'افتح التطبيق لمراجعة حالة الطلب والتواصل مع الدعم.' };
    case 'request.cancelled':
      return effectiveRole === 'NURSE'
        ? { title: 'ألغى المريض الطلب', body: 'تم إلغاء الزيارة من قبل المريض.' }
        : { title: 'تم إلغاء الطلب', body: 'تم تحديث حالة طلبك إلى ملغى.' };
    case 'cancellation.appeal.resolved':
      return { title: 'تمت مراجعة الاعتراض', body: 'افتح التطبيق للاطلاع على النتيجة.' };
    case 'offer.created':
      if (effectiveRole === 'PATIENT') return null;
      return { title: 'طلب تمريض جديد قريب منك', body: 'لديك عرض محدود المدة، افتح التطبيق للقبول.' };
    case 'request.created':
      return { title: 'تم إنشاء طلبك', body: 'جارٍ البحث عن أقرب ممرض مؤهل لخدمتك.' };
    case 'request.assigned':
      return effectiveRole === 'NURSE'
        ? { title: 'تم إسناد الزيارة إليك', body: 'اطلع على تفاصيل الزيارة وابدأ التوجه في الوقت المحدد.' }
        : { title: 'تم قبول طلبك', body: 'تم إسناد طلبك إلى ممرض معتمد، يمكنك متابعة وصوله الآن.' };
    case 'visit.departure_delayed':
      return effectiveRole === 'NURSE'
        ? { title: 'تذكير ببدء التوجه', body: 'لديك زيارة مسندة بانتظار تأكيد الانطلاق.' }
        : null;
    case 'visit.depart':
      return { title: 'الممرض في الطريق', body: 'بدأ الممرض التوجه إلى موقعك، تابع وصوله مباشرة.' };
    case 'visit.arrive':
      return { title: 'وصل الممرض', body: 'الممرض عند موقع الزيارة الآن.' };
    case 'visit.start':
      return { title: 'بدأت الزيارة', body: 'تم بدء تنفيذ الرعاية التمريضية.' };
    case 'visit.complete':
      return { title: 'انتهت الزيارة', body: 'تم إنهاء الزيارة وصدرت الفاتورة في التطبيق.' };
    case 'payment.partial':
    case 'payment.partially_paid':
      return { title: 'تم تسجيل دفعة جزئية', body: 'افتح التطبيق لمعرفة المبلغ المتبقي.' };
    case 'payment.paid':
      return { title: 'تم تسجيل الدفع بالكامل', body: 'شكرًا لك، يمكنك تقييم الزيارة الآن.' };
    case 'payment.tip':
      return effectiveRole === 'NURSE'
        ? { title: 'إكرامية جديدة', body: 'أضاف المريض إكرامية إلى الزيارة.' }
        : null;
    case 'request.unfulfilled':
      return { title: 'تعذر إيجاد ممرض حاليًا', body: 'يمكنك إعادة المحاولة أو نشر الطلب في السوق المفتوح.' };
    case 'request.schedule_released':
      return { title: 'تذكير بالحجز المجدول', body: 'اقترب موعد زيارتك وجارٍ متابعة تجهيز الممرض.' };
    case 'request.clinical_review_changed':
      return payload.decision === 'REJECTED'
        ? { title: 'نتيجة المراجعة الطبية', body: 'يرجى فتح التطبيق لمراجعة ملاحظات الفريق الطبي.' }
        : { title: 'تمت الموافقة الطبية على طلبك', body: 'طلبك جاهز الآن وتم بدء البحث عن ممرض.' };
    case 'marketplace.proposal.created':
      if (effectiveRole === 'NURSE') return null;
      return { title: 'وصلك عرض استعداد جديد', body: 'يمكنك مراجعة تفاصيل الممرض ووقت الوصول واختيار الأنسب.' };
    case 'marketplace.proposal.accepted':
      return { title: 'وافق المريض على عرضك', body: 'تم تأكيد زيارتك، يمكنك الاطلاع على التفاصيل وتأكيد الانطلاق.' };
    case 'marketplace.proposal.withdrawn':
      return { title: 'تم سحب عرض استعداد', body: 'قام الممرض بسحب عرضه، يمكنك مراجعة العروض الأخرى.' };
    case 'marketplace.recovery.alert':
      if (effectiveRole === 'PATIENT') return null;
      return { title: 'طلبات متاحة في السوق المفتوح', body: 'توجد طلبات تمريضية مفتوحة تتوافق مع اختصاصك ومناطق عملك.' };
    case 'marketplace.request.published':
      return effectiveRole === 'NURSE'
        ? { title: 'طلب رعاية مفتوح', body: 'تم نشر طلب رعاية جديد في نطاقك، يمكنك إرسال عرض استعداد.' }
        : { title: 'تم نشر طلبك في السوق المفتوح', body: 'طلبك متاح الآن لاستقبال عروض الجاهزية من الممرضين.' };
    case 'marketplace.request.updated':
      return { title: 'تم تمديد مهلة الطلب', body: 'تم تحديث وقت استقبال العروض على طلبك.' };
    case 'request.instant.search.expired':
      return { title: 'انتهت مهلة البحث الفوري', body: 'يمكنك نشر طلبك في السوق المفتوح لاستقبال العروض.' };
    case 'call.incoming':
      return effectiveRole === 'NURSE'
        ? { title: 'مكالمة واردة من المريض', body: 'اضغط للرد على المكالمة الصوتية عبر تمريضي.' }
        : { title: 'مكالمة واردة من الممرض', body: 'اضغط للرد على المكالمة الصوتية عبر تمريضي.' };
    case 'call.missed':
      return { title: 'مكالمة فائتة', body: 'لديك مكالمة فائتة مرتبطة بالزيارة النشطة.' };
    case 'chat.message': {
      const snippet = typeof payload.snippet === 'string' && payload.snippet.trim()
        ? payload.snippet.trim()
        : 'لديك رسالة جديدة بخصوص الزيارة.';
      return { title: 'وصلتك رسالة جديدة', body: snippet };
    }
    case 'safety.checkin_due':
    case 'safety.checkin_reminder':
      return effectiveRole === 'NURSE'
        ? { title: 'تأكيد السلامة مطلوب', body: 'يرجى تأكيد سلامتك الآن داخل مركز الأمان.' }
        : null;
    case 'safety.event_changed':
      return { title: 'تحديث مركز الأمان', body: 'تم تحديث حالة بلاغ الأمان الخاص بك.' };
    default:
      return null;
  }
}

/** Wake-up alarm for urgent, time-critical events only (new dispatch offer, incoming call, delayed departure). */
export function alarmMessage(token: string, data: Record<string, string>, ttlSeconds: number, copy: { title: string; body: string }) {
  const ttl = Math.max(0, Math.min(300, Math.floor(ttlSeconds)));
  return {
    message: {
      token,
      data: { ...data, alarm: '1', title: copy.title, body: copy.body, ttl: String(ttl) },
      android: { priority: 'HIGH', ttl: `${ttl}s` },
      apns: {
        headers: { 'apns-priority': '10', 'apns-push-type': 'alert', 'apns-expiration': String(Math.floor(Date.now() / 1000) + ttl) },
        payload: { aps: { alert: { title: copy.title, body: copy.body }, sound: 'tamreedy_alert.caf', 'interruption-level': 'time-sensitive' } },
      },
    },
  };
}

export interface ServiceAccount { project_id: string; client_email: string; private_key: string; }
export type SendResult = 'ok' | 'unregistered' | 'error';
export interface PushResponse { result: SendResult; errorDetail?: string; }
type Fetch = typeof fetch;

/** Minimal FCM HTTP v1 client (service-account JWT -> OAuth token -> messages:send). */
export class FcmClient {
  private token?: { value: string; exp: number };
  private tokenRequest?: Promise<string>;
  private readonly sa: ServiceAccount;
  private readonly fetchImpl: Fetch;
  private readonly observeResult: ((ok: boolean) => void) | undefined;
  constructor(sa: ServiceAccount, fetchImpl: Fetch = fetch, observeResult?: (ok: boolean) => void) {
    this.observeResult = observeResult;
    this.sa = sa;
    this.fetchImpl = fetchImpl;
  }

  async accessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.token && this.token.exp - 60 > now) return this.token.value;
    this.tokenRequest ??= this.fetchAccessToken(now).finally(() => {
      this.tokenRequest = undefined;
    });
    return this.tokenRequest;
  }

  private async fetchAccessToken(now: number): Promise<string> {
    const assertion = jwt.sign({ scope: 'https://www.googleapis.com/auth/firebase.messaging' }, this.sa.private_key, {
      algorithm: 'RS256', issuer: this.sa.client_email, audience: 'https://oauth2.googleapis.com/token', expiresIn: 3600,
    });
    const r = await this.fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST', signal: AbortSignal.timeout(4000), headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    if (!r.ok) throw new Error(`fcm oauth ${r.status}`);
    const j = await r.json() as { access_token: string; expires_in: number };
    this.token = { value: j.access_token, exp: now + j.expires_in };
    return j.access_token;
  }

  async send(deviceToken: string, msg: { title: string; body: string }, data: Record<string, string>): Promise<SendResult> {
    const r = await this.post({ message: { token: deviceToken, notification: msg, data, android: { priority: 'HIGH' }, apns: { headers: { 'apns-priority': '10' } } } });
    return r.result;
  }

  async sendAlarm(deviceToken: string, data: Record<string, string>, ttlSeconds: number, copy: { title: string; body: string }): Promise<SendResult> {
    const r = await this.post(alarmMessage(deviceToken, data, ttlSeconds, copy));
    return r.result;
  }

  async sendDetailed(deviceToken: string, msg: { title: string; body: string }, data: Record<string, string>): Promise<PushResponse> {
    return this.post({ message: { token: deviceToken, notification: msg, data, android: { priority: 'HIGH' }, apns: { headers: { 'apns-priority': '10' } } } });
  }

  async sendAlarmDetailed(deviceToken: string, data: Record<string, string>, ttlSeconds: number, copy: { title: string; body: string }): Promise<PushResponse> {
    return this.post(alarmMessage(deviceToken, data, ttlSeconds, copy));
  }

  async sendClosureDetailed(deviceToken: string, data: Record<string, string>): Promise<PushResponse> {
    return this.post({ message: { token: deviceToken, data,
      android: { priority: 'HIGH', ttl: '300s' },
      apns: { headers: { 'apns-priority': '5', 'apns-push-type': 'background' },
        payload: { aps: { 'content-available': 1 } } },
    } });
  }

  private async post(body: unknown): Promise<PushResponse> {
    try {
      const token = await this.accessToken();
      const r = await this.fetchImpl(`https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`, {
        method: 'POST', signal: AbortSignal.timeout(4000), headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (r.ok) {
        this.observeResult?.(true);
        return { result: 'ok' };
      }
      const errText = await r.text();
      let e: any = {};
      try { e = JSON.parse(errText); } catch {}
      if (r.status === 404 || r.status === 400) {
        if (e.error?.details?.some((d: any) => d.errorCode === 'UNREGISTERED') || e.error?.status === 'NOT_FOUND') {
          return { result: 'unregistered', errorDetail: 'Device token no longer registered' };
        }
      }
      this.observeResult?.(false);
      return { result: 'error', errorDetail: `HTTP ${r.status}` };
    } catch (err: any) {
      this.observeResult?.(false);
      return { result: 'error', errorDetail: 'FCM transport failed' };
    }
  }
}

export interface OutboxEvent {
  id: string | number;
  event_type: string;
  created_at?: string;
  payload: {
    eventId?: string;
    eventType?: string;
    recipientUserId?: string;
    recipientUserIds?: string[];
    recipientRole?: string;
    targetApp?: string;
    requestId?: string | null;
    assignmentId?: string | null;
    offerId?: string | null;
    proposalId?: string | null;
    callId?: string | null;
    conversationId?: string | null;
    entityVersion?: number | null;
    createdAt?: string | null;
    expiresAt?: string | null;
    priority?: string | null;
    deepLink?: string | null;
    sessionVersion?: number;
    callerRole?: string;
    ringExpiresAt?: string;
    skipPush?: boolean;
    snippet?: string;
    percent?: number;
    decision?: string;
  };
}
export interface Db { query: (sql: string, params?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }>; }

const ALARM_EVENT_TYPES = new Set([
  'offer.created',
  'visit.departure_delayed',
  'call.incoming',
]);

async function openOfferIds(db: Db, offerIds: string[]): Promise<Set<string>> {
  const ids = [...new Set(offerIds.filter(id => /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(id)))];
  if (!ids.length) return new Set();
  const result = await db.query(`
    SELECT o.id FROM request_offers o JOIN care_requests r ON r.id=o.request_id
    WHERE o.id=ANY($1::uuid[]) AND o.status='OPEN' AND o.expires_at>now() AND r.status='OFFERING'
  `, [ids]);
  return new Set(result.rows.map(row => String(row.id)));
}

function buildFcmDataMap(e: OutboxEvent, userId: string, role?: string, targetApp?: string): Record<string, string> {
  const p = e.payload ?? {};
  const eventId = p.eventId ? String(p.eventId) : String(e.id);
  const eventType = p.eventType ? String(p.eventType) : e.event_type;
  const resolvedRole = role ?? (p.recipientRole ? String(p.recipientRole) : '');
  const resolvedApp = targetApp ?? (p.targetApp ? String(p.targetApp) : (targetAppForRole(resolvedRole) ?? ''));
  const deepLink = p.deepLink ? String(p.deepLink) : deepLinkForPush(eventType, resolvedRole || undefined, p);

  return {
    eventId,
    eventType,
    type: eventType,
    recipientUserId: userId,
    recipientRole: resolvedRole,
    targetApp: resolvedApp,
    requestId: p.requestId ? String(p.requestId) : '',
    assignmentId: p.assignmentId ? String(p.assignmentId) : '',
    offerId: p.offerId ? String(p.offerId) : '',
    proposalId: p.proposalId ? String(p.proposalId) : '',
    conversationId: p.conversationId ? String(p.conversationId) : '',
    callId: p.callId ? String(p.callId) : '',
    entityVersion: p.entityVersion != null ? String(p.entityVersion) : '',
    sessionVersion: p.sessionVersion != null ? String(p.sessionVersion) : '',
    callerRole: p.callerRole ? String(p.callerRole) : '',
    ringExpiresAt: p.ringExpiresAt ? String(p.ringExpiresAt) : '',
    createdAt: p.createdAt ? String(p.createdAt) : (e.created_at ? String(e.created_at) : new Date().toISOString()),
    expiresAt: p.expiresAt ? String(p.expiresAt) : '',
    priority: p.priority ? String(p.priority) : (ALARM_EVENT_TYPES.has(eventType) ? 'CRITICAL' : 'HIGH'),
    deepLink,
  };
}

/** Sends pushes for a batch of events with strict role/app token isolation and decoupled ledger logging. */
export async function pushDeliverBatch(
  db: Db,
  fcm: FcmClient,
  events: OutboxEvent[]
): Promise<{ sent: number; failed: number; pruned: number }> {
  const offers = events.filter(e => e.event_type === 'offer.created');
  const open = await openOfferIds(db, offers.map(e => e.payload.offerId ?? ''));
  const hasAlarmCandidate = events.some(e =>
    e.event_type === 'offer.created' ? open.has(e.payload.offerId ?? '') : ALARM_EVENT_TYPES.has(e.event_type),
  );
  const alarmOn = hasAlarmCandidate && await alarmEnabled(db);

  const planned = events.flatMap(e => {
    if (e.payload?.skipPush === true) return [];
    if (e.event_type === 'offer.created' && !open.has(e.payload.offerId ?? '')) return [];
    if (e.payload?.recipientRole === 'ADMIN' || e.payload?.targetApp === 'ADMIN_WEB') return [];

    const copy = pushCopy(e.event_type, e.payload, e.payload?.recipientRole);
    if (!copy) return [];
    const users = [...new Set([...(e.payload.recipientUserIds ?? []), ...(e.payload.recipientUserId ? [e.payload.recipientUserId] : [])])];
    const alarm = alarmOn && ALARM_EVENT_TYPES.has(e.event_type);
    const expiresAt = e.payload.expiresAt ? new Date(e.payload.expiresAt) : null;
    const recipientRole = e.payload.recipientRole ? String(e.payload.recipientRole) : undefined;
    const targetApp = e.payload.targetApp ? String(e.payload.targetApp) : targetAppForRole(recipientRole);

    return users.map(u => ({
      eventId: e.id,
      user: u,
      recipientRole,
      targetApp,
      copy,
      alarm,
      expiresAt,
      data: buildFcmDataMap(e, u, recipientRole, targetApp),
    }));
  });

  if (!planned.length) return { sent: 0, failed: 0, pruned: 0 };

  const uniqueUsers = [...new Set(planned.map(p => p.user))];
  // BUG-027: Migration 063 + device_sessions isolation is mandatory; never fall back to unisolated token queries.
  const tokenRows = (
    await db.query(
      `SELECT dt.user_id, dt.token, dt.platform, dt.app_type, dt.role AS token_role, u.role AS user_role
       FROM device_tokens dt
       JOIN users u ON u.id = dt.user_id AND u.status = 'ACTIVE'
       JOIN device_sessions ds ON ds.id = dt.session_id AND ds.user_id = dt.user_id AND ds.revoked_at IS NULL
       WHERE dt.user_id = ANY($1::uuid[])
         AND dt.active_status = 'ACTIVE'
         AND dt.role = u.role
         AND dt.app_type = CASE u.role WHEN 'NURSE' THEN 'NURSE_APP' WHEN 'PATIENT' THEN 'PATIENT_APP' END`,
      [uniqueUsers],
    )
  ).rows;

  const byUser = new Map<string, { token: string; platform: string; appType?: string; tokenRole?: string; userRole?: string }[]>();
  for (const r of tokenRows) {
    byUser.set(r.user_id, [
      ...(byUser.get(r.user_id) ?? []),
      {
        token: r.token,
        platform: r.platform,
        appType: r.app_type ?? undefined,
        tokenRole: r.token_role ?? undefined,
        userRole: r.user_role ?? undefined,
      },
    ]);
  }

  const ledger = await db.query(`
    SELECT event_id,recipient_user_id,device_token FROM notification_deliveries
    WHERE event_id=ANY($1::bigint[]) AND channel='FCM_PUSH'
  `, [[...new Set(planned.map(item => String(item.eventId)))]]);
  const recorded = new Set(ledger.rows.map(row => JSON.stringify([
    String(row.event_id), row.recipient_user_id, row.device_token,
  ])));
  const deliveryKey = (item: typeof planned[number], token: string | null) =>
    JSON.stringify([String(item.eventId), item.user, token]);

  const deadTokens: string[] = [];
  let sentCount = 0;
  let failedCount = 0;

  const deliver = async (item: typeof planned[number]) => {
    const rawDevices = byUser.get(item.user) ?? [];
    // Strict role/app isolation: never deliver if token role/appType is missing or mismatched
    const devices = rawDevices.filter(dev => {
      if (item.recipientRole) {
        if (!dev.userRole || dev.userRole !== item.recipientRole) return false;
        if (!dev.tokenRole || dev.tokenRole !== item.recipientRole) return false;
      }
      if (item.targetApp) {
        if (!dev.appType || dev.appType !== item.targetApp) return false;
      }
      return true;
    });

    if (!devices.length) {
      if (recorded.has(deliveryKey(item, null))) return;
      await db.query(
        `INSERT INTO notification_deliveries(
          event_id, recipient_user_id, channel, status, attempts, last_error_code, last_error_detail, payload, expires_at
        ) VALUES($1, $2, 'FCM_PUSH', 'FAILED', 1, 'NO_DEVICE_TOKEN', 'User has no matching active device tokens', $3::jsonb, $4)`,
        [item.eventId, item.user, JSON.stringify(item.data), item.expiresAt]
      );
      failedCount++;
      return;
    }

    for (const dev of devices) {
      if (recorded.has(deliveryKey(item, dev.token))) continue;
      if (item.expiresAt && item.expiresAt.getTime() <= Date.now()) {
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, last_error_code, last_error_detail, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'FAILED', 1, 'OFFER_EXPIRED', 'Offer expired prior to delivery attempt', $4::jsonb, $5)`,
          [item.eventId, item.user, dev.token, JSON.stringify(item.data), item.expiresAt]
        );
        failedCount++;
        continue;
      }

      // Re-check immediately before transport delivery: an earlier query must not
      // authorize a token after logout or reassignment to a different account.
      const valid = await db.query(`SELECT 1 FROM device_tokens dt
        JOIN users u ON u.id=dt.user_id AND u.status='ACTIVE' AND u.role=dt.role
        JOIN device_sessions ds ON ds.id=dt.session_id AND ds.user_id=dt.user_id AND ds.revoked_at IS NULL
        WHERE dt.token=$1 AND dt.user_id=$2 AND dt.active_status='ACTIVE'
          AND dt.role=$3 AND dt.app_type=$4`,[dev.token,item.user,dev.tokenRole,dev.appType]);
      if (!valid.rowCount) continue;
      const resolvedRole = item.recipientRole ?? dev.userRole ?? item.data.recipientRole ?? '';
      const eventType = item.data.type ?? '';
      const copy = pushCopy(eventType, item.data, resolvedRole || undefined) ?? item.copy;
      const payloadData: Record<string, string> = {
        ...item.data,
        recipientRole: resolvedRole,
        targetApp: targetAppForRole(resolvedRole) ?? item.data.targetApp ?? '',
      };

      if (eventType === 'call.incoming' && !await callIsRinging(db, payloadData.callId, item.user, payloadData.sessionVersion)) continue;

      const ttl = item.expiresAt ? (item.expiresAt.getTime() - Date.now()) / 1000 : 45;
      const res = ['offer.closed', 'offer.expired'].includes(eventType)
        ? await fcm.sendClosureDetailed(dev.token, payloadData)
        : item.alarm
          ? await fcm.sendAlarmDetailed(dev.token, payloadData, ttl, copy)
          : await fcm.sendDetailed(dev.token, copy, payloadData);

      if (res.result === 'ok') {
        sentCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, sent_at, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'SENT', 1, now(), $4::jsonb, $5)`,
          [item.eventId, item.user, dev.token, JSON.stringify(payloadData), item.expiresAt]
        );
      } else if (res.result === 'unregistered') {
        deadTokens.push(dev.token);
        failedCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, last_error_code, last_error_detail, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'UNREGISTERED', 1, 'UNREGISTERED', $4, $5::jsonb, $6)`,
          [item.eventId, item.user, dev.token, res.errorDetail ?? 'Token unregistered by FCM', JSON.stringify(payloadData), item.expiresAt]
        );
      } else {
        failedCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, next_attempt_at, last_error_code, last_error_detail, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'FAILED', 1, now() + interval '5 seconds', 'FCM_ERROR', $4, $5::jsonb, $6)`,
          [item.eventId, item.user, dev.token, res.errorDetail ?? 'Delivery failed', JSON.stringify(payloadData), item.expiresAt]
        );
      }
    }
  };

  const concurrency = 10;
  for (let offset = 0; offset < planned.length; offset += concurrency) {
    const results = await Promise.allSettled(planned.slice(offset, offset + concurrency).map(deliver));
    const failure = results.find(result => result.status === 'rejected');
    if (failure?.status === 'rejected') throw failure.reason;
  }

  if (deadTokens.length) {
    await db.query('DELETE FROM device_tokens WHERE token=ANY($1::text[])', [deadTokens]);
  }

  return { sent: sentCount, failed: failedCount, pruned: deadTokens.length };
}

/** Retries any failed notification deliveries whose offers have not expired. */
export async function retryPendingPushes(db: Db, fcm: FcmClient): Promise<number> {
  const lease = randomUUID();
  const pending = await db.query(`
    WITH due AS (
      SELECT id FROM notification_deliveries
      WHERE status='FAILED' AND attempts<max_attempts AND next_attempt_at<=statement_timestamp()
        AND (expires_at IS NULL OR expires_at>statement_timestamp())
        AND (retry_lease_until IS NULL OR retry_lease_until<=statement_timestamp())
      ORDER BY next_attempt_at,id LIMIT 20 FOR UPDATE SKIP LOCKED
    )
    UPDATE notification_deliveries d SET retry_lease_token=$1,
      retry_lease_until=statement_timestamp()+interval '3 minutes'
    FROM due WHERE d.id=due.id RETURNING d.*
  `, [lease]);

  if (!pending.rowCount) return 0;

  const open = await openOfferIds(db, pending.rows
    .filter(row => row.payload?.type === 'offer.created')
    .map(row => row.payload.offerId ?? ''));
  const hasRetryAlarm = pending.rows.some(row => {
    const t = row.payload?.type;
    return t === 'offer.created' ? open.has(row.payload?.offerId ?? '') : ALARM_EVENT_TYPES.has(t);
  });
  const alarmOn = hasRetryAlarm && await alarmEnabled(db);
  let retriedCount = 0;
  for (const row of pending.rows) {
    const finish = (changes: string, values: unknown[] = []) => db.query(`
      UPDATE notification_deliveries SET ${changes},retry_lease_token=NULL,retry_lease_until=NULL
      WHERE id=$1 AND retry_lease_token=$2
    `,[row.id,lease,...values]);
    const payload = typeof row.payload === 'object' ? row.payload : {};
    const expectedRole = typeof payload.recipientRole === 'string' && payload.recipientRole ? payload.recipientRole : null;
    const expectedApp = typeof payload.targetApp === 'string' && payload.targetApp ? payload.targetApp : null;
    const deviceCount = (await db.query(
      `SELECT 1 FROM device_tokens dt
       JOIN users u ON u.id = dt.user_id AND u.status = 'ACTIVE'
       JOIN device_sessions ds ON ds.id = dt.session_id AND ds.user_id = dt.user_id AND ds.revoked_at IS NULL
       WHERE dt.token = $1
         AND dt.user_id = $2
         AND dt.active_status = 'ACTIVE'
         AND dt.role = u.role
         AND dt.app_type = CASE u.role WHEN 'NURSE' THEN 'NURSE_APP' WHEN 'PATIENT' THEN 'PATIENT_APP' END
         AND $3::text IS NOT NULL AND u.role = $3 AND dt.role = $3
         AND $4::text IS NOT NULL AND dt.app_type = $4`,
      [row.device_token, row.recipient_user_id, expectedRole, expectedApp],
    )).rowCount;
    if (!row.device_token || !deviceCount) {
      await finish("status='ABANDONED'");
      continue;
    }

    const copy = pushCopy(payload.type, payload, payload.recipientRole);
    const isOffer = payload.type === 'offer.created';
    if (!copy || (isOffer && !open.has(payload.offerId)) ||
        (payload.type === 'call.incoming' && !await callIsRinging(db, payload.callId, row.recipient_user_id, payload.sessionVersion))) {
      await finish("status='ABANDONED'");
      continue;
    }

    const isAlarm = ALARM_EVENT_TYPES.has(payload.type) && alarmOn;
    const expiresAt = row.expires_at ? new Date(row.expires_at) : null;
    const ttl = expiresAt ? (expiresAt.getTime() - Date.now()) / 1000 : 45;
    if (ttl <= 0) {
      await finish("status='ABANDONED'");
      continue;
    }

    const res = ['offer.closed','offer.expired'].includes(payload.type)
      ? await fcm.sendClosureDetailed(row.device_token,payload)
      : isAlarm
        ? await fcm.sendAlarmDetailed(row.device_token, payload, ttl, copy)
        : await fcm.sendDetailed(row.device_token, copy, payload);

    if (res.result === 'ok') {
      retriedCount++;
      await finish("status='SENT',sent_at=statement_timestamp(),attempts=attempts+1");
    } else if (res.result === 'unregistered') {
      await finish("status='UNREGISTERED',attempts=attempts+1,last_error_code='UNREGISTERED',last_error_detail=$3",[res.errorDetail]);
      await db.query(`DELETE FROM device_tokens WHERE token=$1`, [row.device_token]);
    } else {
      const delaySeconds = 5 * 2 ** Number(row.attempts);
      await finish("attempts=attempts+1,next_attempt_at=statement_timestamp()+$3::integer*interval '1 second',last_error_detail=$4",
        [delaySeconds,res.errorDetail]);
    }
  }

  return retriedCount;
}

export async function pushBatch(db: Db, fcm: Pick<FcmClient, 'send' | 'sendAlarm'>, events: OutboxEvent[]): Promise<{ sent: number; pruned: number }> {
  if (fcm instanceof FcmClient) {
    const res = await pushDeliverBatch(db, fcm, events);
    return { sent: res.sent, pruned: res.pruned };
  }
  return { sent: 0, pruned: 0 };
}

async function alarmEnabled(db: Db): Promise<boolean> {
  try { return (await db.query(`SELECT enabled FROM marketing_features WHERE key='alarm'`)).rows[0]?.enabled ?? true; } catch { return true; }
}

export function loadServiceAccount(raw: string | undefined): ServiceAccount | undefined {
  if (!raw?.trim()) return undefined;
  try {
    const sa = JSON.parse(raw) as ServiceAccount;
    if (typeof sa.project_id !== 'string' || !sa.project_id.trim() ||
        typeof sa.client_email !== 'string' || !sa.client_email.includes('@') ||
        typeof sa.private_key !== 'string' || createPrivateKey(sa.private_key).asymmetricKeyType !== 'rsa') {
      console.warn('[FCM] Incomplete service account structure');
      return undefined;
    }
    return sa;
  } catch {
    console.warn('[FCM] Invalid service account configuration');
    return undefined;
  }
}
