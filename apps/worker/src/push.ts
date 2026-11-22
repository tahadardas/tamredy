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
export interface PushResponse { result: SendResult; errorDetail?: string; }
type Fetch = typeof fetch;

/** Minimal FCM HTTP v1 client (service-account JWT -> OAuth token -> messages:send). */
export class FcmClient {
  private token?: { value: string; exp: number };
  private readonly sa: ServiceAccount;
  private readonly fetchImpl: Fetch;
  constructor(sa: ServiceAccount, fetchImpl: Fetch = fetch) { this.sa = sa; this.fetchImpl = fetchImpl; }

  async accessToken(): Promise<string> {
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

  private async post(body: unknown): Promise<PushResponse> {
    try {
      const token = await this.accessToken();
      const r = await this.fetchImpl(`https://fcm.googleapis.com/v1/projects/${this.sa.project_id}/messages:send`, {
        method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(body),
      });
      if (r.ok) return { result: 'ok' };
      const errText = await r.text();
      let e: any = {};
      try { e = JSON.parse(errText); } catch {}
      if (r.status === 404 || r.status === 400) {
        if (e.error?.details?.some((d: any) => d.errorCode === 'UNREGISTERED') || e.error?.status === 'NOT_FOUND') {
          return { result: 'unregistered', errorDetail: errText };
        }
      }
      return { result: 'error', errorDetail: `HTTP ${r.status}: ${errText}` };
    } catch (err: any) {
      return { result: 'error', errorDetail: err?.message || String(err) };
    }
  }
}

export interface OutboxEvent {
  id: string | number;
  event_type: string;
  payload: {
    recipientUserId?: string;
    recipientUserIds?: string[];
    requestId?: string;
    offerId?: string;
    expiresAt?: string;
    percent?: number;
  };
}
export interface Db { query: (sql: string, params?: unknown[]) => Promise<{ rows: any[]; rowCount: number | null }>; }

/** Sends pushes for a batch of events with decoupled ledger logging in notification_deliveries. */
export async function pushDeliverBatch(
  db: Db,
  fcm: FcmClient,
  events: OutboxEvent[]
): Promise<{ sent: number; failed: number; pruned: number }> {
  const alarmOn = events.some(e => e.event_type === 'offer.created') ? await alarmEnabled(db) : false;

  const planned = events.flatMap(e => {
    const copy = pushCopy(e.event_type, e.payload);
    if (!copy) return [];
    const users = [...(e.payload.recipientUserIds ?? []), ...(e.payload.recipientUserId ? [e.payload.recipientUserId] : [])];
    const alarm = alarmOn && e.event_type === 'offer.created';
    const expiresAt = e.payload.expiresAt ? new Date(e.payload.expiresAt) : null;
    const ttl = expiresAt ? (expiresAt.getTime() - Date.now()) / 1000 : 20;

    return users.map(u => ({
      eventId: e.id,
      user: u,
      copy,
      alarm,
      ttl,
      expiresAt,
      data: {
        type: e.event_type,
        requestId: e.payload.requestId ?? '',
        offerId: e.payload.offerId ?? '',
        expiresAt: e.payload.expiresAt ?? '',
      },
    }));
  });

  if (!planned.length) return { sent: 0, failed: 0, pruned: 0 };

  const uniqueUsers = [...new Set(planned.map(p => p.user))];
  const tokenRows = (
    await db.query(
      'SELECT user_id, token, platform FROM device_tokens WHERE user_id=ANY($1::uuid[])',
      [uniqueUsers]
    )
  ).rows;

  const byUser = new Map<string, { token: string; platform: string }[]>();
  for (const r of tokenRows) {
    byUser.set(r.user_id, [...(byUser.get(r.user_id) ?? []), { token: r.token, platform: r.platform }]);
  }

  const deadTokens: string[] = [];
  let sentCount = 0;
  let failedCount = 0;

  for (const item of planned) {
    const devices = byUser.get(item.user) ?? [];
    if (!devices.length) {
      // Record token missing in delivery ledger
      await db.query(
        `INSERT INTO notification_deliveries(
          event_id, recipient_user_id, channel, status, attempts, last_error_code, last_error_detail, payload, expires_at
        ) VALUES($1, $2, 'FCM_PUSH', 'FAILED', 1, 'NO_DEVICE_TOKEN', 'User has no registered active device tokens', $3::jsonb, $4)`,
        [item.eventId, item.user, JSON.stringify(item.data), item.expiresAt]
      );
      failedCount++;
      continue;
    }

    for (const dev of devices) {
      // Check if offer expired before attempting push
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

      const res = item.alarm
        ? await fcm.sendAlarmDetailed(dev.token, item.data, item.ttl, item.copy)
        : await fcm.sendDetailed(dev.token, item.copy, item.data);

      if (res.result === 'ok') {
        sentCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, sent_at, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'SENT', 1, now(), $4::jsonb, $5)`,
          [item.eventId, item.user, dev.token, JSON.stringify(item.data), item.expiresAt]
        );
      } else if (res.result === 'unregistered') {
        deadTokens.push(dev.token);
        failedCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, last_error_code, last_error_detail, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'UNREGISTERED', 1, 'UNREGISTERED', $4, $5::jsonb, $6)`,
          [item.eventId, item.user, dev.token, res.errorDetail ?? 'Token unregistered by FCM', JSON.stringify(item.data), item.expiresAt]
        );
      } else {
        failedCount++;
        await db.query(
          `INSERT INTO notification_deliveries(
            event_id, recipient_user_id, device_token, channel, status, attempts, next_attempt_at, last_error_code, last_error_detail, payload, expires_at
          ) VALUES($1, $2, $3, 'FCM_PUSH', 'FAILED', 1, now() + interval '5 seconds', 'FCM_ERROR', $4, $5::jsonb, $6)`,
          [item.eventId, item.user, dev.token, res.errorDetail ?? 'Delivery failed', JSON.stringify(item.data), item.expiresAt]
        );
      }
    }
  }

  if (deadTokens.length) {
    await db.query('DELETE FROM device_tokens WHERE token=ANY($1::text[])', [deadTokens]);
  }

  return { sent: sentCount, failed: failedCount, pruned: deadTokens.length };
}

/** Retries any failed notification deliveries whose offers have not expired. */
export async function retryPendingPushes(db: Db, fcm: FcmClient): Promise<number> {
  const pending = await db.query(`
    SELECT id, recipient_user_id, device_token, attempts, max_attempts, payload, expires_at
    FROM notification_deliveries
    WHERE status = 'FAILED'
      AND attempts < max_attempts
      AND next_attempt_at <= now()
      AND (expires_at IS NULL OR expires_at > now())
    ORDER BY next_attempt_at ASC
    LIMIT 20
    FOR UPDATE SKIP LOCKED
  `);

  if (!pending.rowCount) return 0;

  let retriedCount = 0;
  for (const row of pending.rows) {
    if (!row.device_token) {
      await db.query(`UPDATE notification_deliveries SET status='ABANDONED' WHERE id=$1`, [row.id]);
      continue;
    }

    const payload = typeof row.payload === 'object' ? row.payload : {};
    const copy = pushCopy(payload.type, payload);
    if (!copy) {
      await db.query(`UPDATE notification_deliveries SET status='ABANDONED' WHERE id=$1`, [row.id]);
      continue;
    }

    const isAlarm = payload.type === 'offer.created';
    const expiresAt = row.expires_at ? new Date(row.expires_at) : null;
    const ttl = expiresAt ? Math.max(2, (expiresAt.getTime() - Date.now()) / 1000) : 20;

    const res = isAlarm
      ? await fcm.sendAlarmDetailed(row.device_token, payload, ttl, copy)
      : await fcm.sendDetailed(row.device_token, copy, payload);

    if (res.result === 'ok') {
      retriedCount++;
      await db.query(`UPDATE notification_deliveries SET status='SENT', sent_at=now(), attempts=attempts+1 WHERE id=$1`, [row.id]);
    } else if (res.result === 'unregistered') {
      await db.query(`UPDATE notification_deliveries SET status='UNREGISTERED', attempts=attempts+1, last_error_code='UNREGISTERED', last_error_detail=$2 WHERE id=$1`, [row.id, res.errorDetail]);
      await db.query(`DELETE FROM device_tokens WHERE token=$1`, [row.device_token]);
    } else {
      const nextDelay = (row.attempts + 1) * 5;
      await db.query(`UPDATE notification_deliveries SET attempts=attempts+1, next_attempt_at=now()+($2||' seconds')::interval, last_error_detail=$3 WHERE id=$1`, [row.id, String(nextDelay), res.errorDetail]);
    }
  }

  return retriedCount;
}

// Kept for backward compatibility
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
  if (!raw?.trim()) return undefined; // empty placeholder file = push disabled
  try {
    const sa = JSON.parse(raw) as ServiceAccount;
    if (!sa.project_id || !sa.client_email || !sa.private_key) {
      console.warn('[FCM] Incomplete service account structure');
      return undefined;
    }
    return sa;
  } catch (e) {
    console.warn('[FCM] Failed to parse service account JSON:', e);
    return undefined;
  }
}
