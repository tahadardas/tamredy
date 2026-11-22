import jwt from 'jsonwebtoken';

/** Push copy per outbox event type. Messages never contain names, addresses or
 *  medical details: the app fetches details over REST after opening. */
export function pushCopy(type: string, payload: Record<string, any> = {}): { title: string; body: string } | null {
  switch (type) {
    case 'winback.offer': return { title: 'اشتقنا لك 💙', body: `خصم ${payload.percent ?? ''}% على طلبك القادم — صالح لفترة محدودة.` };
    case 'pack.granted': return { title: 'تم تفعيل باقتك', body: 'خصم باقتك يُطبَّق تلقائيًا على زياراتك القادمة.' };
    case 'offer.created': return { title: 'طلب جديد قريب منك', body: 'لديك عرض محدود المدة، افتح التطبيق للقبول.' };
    case 'request.assigned': return { title: 'تم قبول طلبك', body: 'تم إسناد طلبك إلى ممرض معتمد.' };
    case 'visit.depart': return { title: 'الممرض في الطريق', body: 'يمكنك متابعة وصوله من التطبيق.' };
    case 'visit.arrive': return { title: 'وصل الممرض', body: 'الممرض عند موقع الزيارة.' };
    case 'visit.complete': return { title: 'تمت الزيارة', body: 'المبلغ المطلوب جاهز في التطبيق.' };
    case 'payment.partial': return { title: 'تم تسجيل دفعة جزئية', body: 'افتح التطبيق لمعرفة المبلغ المتبقي.' };
    case 'payment.paid': return { title: 'تم الدفع بالكامل', body: 'شكرًا لك، يسعدنا تقييمك للخدمة.' };
    case 'request.unfulfilled': return { title: 'تعذر العثور على ممرض', body: 'لم يتوفر ممرض الآن، يمكنك إعادة المحاولة.' };
    default: return null;
  }
}

/** Wake-up alarm for a new request. DATA-ONLY on Android (no `notification` block) so the app's background handler runs and raises an
 *  insistent, loud, full-screen alert with the distinctive tone; the TTL equals the offer lifetime so a stale offer is never delivered late.
 *  iOS gets a time-sensitive alert with the bundled long sound (a Critical Alert needs a special Apple entitlement). */
export function alarmMessage(token: string, data: Record<string, string>, ttlSeconds: number, copy: { title: string; body: string }) {
  const ttl = Math.max(5, Math.min(60, Math.round(ttlSeconds)));
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
type Fetch = typeof fetch;

/** Minimal FCM HTTP v1 client (service-account JWT -> OAuth token -> messages:send). */
export class FcmClient {
  private token?: { value: string; exp: number };
  private readonly sa: ServiceAccount;
  private readonly fetchImpl: Fetch;
  constructor(sa: ServiceAccount, fetchImpl: Fetch = fetch) { this.sa = sa; this.fetchImpl = fetchImpl; }

  private async accessToken(): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    if (this.token && this.token.exp - 60 > now) return this.token.value;
    const assertion = jwt.sign({ scope: 'https://www.googleapis.com/auth/firebase.messaging' }, this.sa.private_key, {
      algorithm: 'RS256', issuer: this.sa.client_email, audience: 'https://oauth2.googleapis.com/token', expiresIn: 3600,
    });
    const r = await this.fetchImpl('https://oauth2.googleapis.com/token', {
      method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    });
    if (!r.ok) throw new Error(`fcm oauth ${r.status}`);
    const j = await r.json() as { access_token: string; expires_in: number };
    this.token = { value: j.access_token, exp: now + j.expires_in };
    return j.access_token;
  }

  async send(deviceToken: string, msg: { title: string; body: string }, data: Record<string, string>): Promise<SendResult> {
    return this.post({ message: { token: deviceToken, notification: msg, data, android: { priority: 'HIGH' }, apns: { headers: { 'apns-priority': '10' } } } });
  }

  async sendAlarm(deviceToken: string, data: Record<string, string>, ttlSeconds: number, copy: { title: string; body: string }): Promise<SendResult> {
    return this.post(alarmMessage(deviceToken, data, ttlSeconds, copy));
  }

  private async post(body: unknown): Promise<SendResult> {
    try {
      const r = await this.fetchImpl(`https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`, {
        method: 'POST', headers: { Authorization: `Bearer ${await this.accessToken()}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (r.ok) return 'ok';
      if (r.status === 404 || r.status === 400) {
        const e = await r.json().catch(() => ({})) as { error?: { details?: { errorCode?: string }[]; status?: string } };
        if (e.error?.details?.some(d => d.errorCode === 'UNREGISTERED') || e.error?.status === 'NOT_FOUND') return 'unregistered';
      }
      return 'error';
    } catch { return 'error'; }
  }
}

export interface OutboxEvent { id: string | number; event_type: string; payload: { recipientUserId?: string; recipientUserIds?: string[]; requestId?: string; offerId?: string; expiresAt?: string; percent?: number }; }
export interface Db { query: (sql: string, params?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }>; }

/** Sends pushes for a batch of events with ONE token lookup (no per-event query) and prunes dead tokens. */
export async function pushBatch(db: Db, fcm: Pick<FcmClient, 'send' | 'sendAlarm'>, events: OutboxEvent[]): Promise<{ sent: number; pruned: number }> {
  // The loud alarm for new requests can be switched off from the marketing page (then offers arrive as normal notifications).
  const alarmOn = events.some(e => e.event_type === 'offer.created') ? await alarmEnabled(db) : false;
  const planned = events.flatMap(e => {
    const copy = pushCopy(e.event_type, e.payload);
    if (!copy) return [];
    const users = [...(e.payload.recipientUserIds ?? []), ...(e.payload.recipientUserId ? [e.payload.recipientUserId] : [])];
    const alarm = alarmOn && e.event_type === 'offer.created';
    const ttl = e.payload.expiresAt ? (new Date(e.payload.expiresAt).getTime() - Date.now()) / 1000 : 20;
    return users.map(u => ({ user: u, copy, alarm, ttl, data: { type: e.event_type, requestId: e.payload.requestId ?? '', offerId: e.payload.offerId ?? '', expiresAt: e.payload.expiresAt ?? '' } }));
  });
  if (!planned.length) return { sent: 0, pruned: 0 };
  const rows = (await db.query('SELECT user_id,token FROM device_tokens WHERE user_id=ANY($1::uuid[])', [[...new Set(planned.map(p => p.user))]])).rows;
  const byUser = new Map<string, string[]>();
  for (const r of rows) byUser.set(r.user_id, [...(byUser.get(r.user_id) ?? []), r.token]);
  const dead: string[] = [];
  let sent = 0;
  await Promise.all(planned.flatMap(p => (byUser.get(p.user) ?? []).map(async t => {
    const res = p.alarm ? await fcm.sendAlarm(t, p.data, p.ttl, p.copy) : await fcm.send(t, p.copy, p.data);
    if (res === 'ok') sent++; else if (res === 'unregistered') dead.push(t);
  })));
  if (dead.length) await db.query('DELETE FROM device_tokens WHERE token=ANY($1::text[])', [dead]);
  return { sent, pruned: dead.length };
}

async function alarmEnabled(db: Db): Promise<boolean> {
  try { return (await db.query(`SELECT enabled FROM marketing_features WHERE key='alarm'`)).rows[0]?.enabled ?? true; } catch { return true; }
}

export function loadServiceAccount(raw: string | undefined): ServiceAccount | undefined {
  if (!raw?.trim()) return undefined; // empty placeholder file = push disabled
  const sa = JSON.parse(raw) as ServiceAccount;
  if (!sa.project_id || !sa.client_email || !sa.private_key) throw new Error('FCM_SERVICE_ACCOUNT_JSON is incomplete');
  return sa;
}
