import { Injectable, NotFoundException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { LiveGateway } from '../realtime/live.gateway.js';

export interface CreateNotificationDto {
  type: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

export interface NotificationPreferencesDto {
  enablePush?: boolean;
  enableInApp?: boolean;
  enableSound?: boolean;
  quietHoursEnabled?: boolean;
  quietHoursStart?: string | null;
  quietHoursEnd?: string | null;
  mutedCategories?: string[];
}

@Injectable()
export class NotificationsService {
  constructor(
    private readonly db: DbService,
    private readonly live: LiveGateway,
  ) {}

  /**
   * Sanitizes payload data to prevent accidental leakage of sensitive tokens or credentials.
   */
  private scrubPayload(data: Record<string, unknown> = {}): Record<string, unknown> {
    const scrubbed = { ...data };
    const sensitiveKeys = ['password', 'token', 'refreshToken', 'secret', 'authCode', 'credit_card'];
    for (const key of Object.keys(scrubbed)) {
      if (sensitiveKeys.some(s => key.toLowerCase().includes(s))) {
        scrubbed[key] = '[REDACTED]';
      }
    }
    return scrubbed;
  }

  /**
   * Dispatches and stores an in-app notification for a user.
   */
  async createNotification(userId: string, dto: CreateNotificationDto) {
    const cleanData = this.scrubPayload(dto.data);

    // Fetch user preferences
    const prefs = await this.getPreferences(userId);
    if (!prefs.enableInApp) {
      // User explicitly disabled in-app notifications
      return null;
    }

    if (prefs.mutedCategories?.includes(dto.type)) {
      // Muted category
      return null;
    }

    const res = await this.db.query(`
      INSERT INTO user_notifications (user_id, type, title, body, data)
      VALUES ($1, $2, $3, $4, $5::jsonb)
      RETURNING id, user_id, type, title, body, data, is_read, read_at, created_at
    `, [userId, dto.type, dto.title, dto.body, JSON.stringify(cleanData)]);

    const notif = res.rows[0];

    // Real-time broadcast to connected client session
    try {
      this.live.sendToUser(userId, 'NOTIFICATION_RECEIVED', {
        id: notif.id,
        type: notif.type,
        title: notif.title,
        body: notif.body,
        data: notif.data,
        createdAt: notif.created_at,
      });
    } catch {
      // Live gateway dispatch is best-effort
    }

    return notif;
  }

  /**
   * Lists notifications with pagination and unread counts.
   */
  async listNotifications(userId: string, options: { limit?: number; offset?: number; unreadOnly?: boolean } = {}) {
    const limit = Math.min(Math.max(options.limit || 20, 1), 100);
    const offset = Math.max(options.offset || 0, 0);

    let whereClause = 'WHERE user_id = $1';
    const params: unknown[] = [userId];

    if (options.unreadOnly) {
      whereClause += ' AND is_read = false';
    }

    const itemsQuery = `
      SELECT id, type, title, body, data, is_read, read_at, created_at
      FROM user_notifications
      ${whereClause}
      ORDER BY created_at DESC
      LIMIT $${params.length + 1} OFFSET $${params.length + 2}
    `;

    const countQuery = `
      SELECT 
        COUNT(*)::int AS total,
        COUNT(CASE WHEN is_read = false THEN 1 END)::int AS unread
      FROM user_notifications
      WHERE user_id = $1
    `;

    const [itemsRes, countRes] = await Promise.all([
      this.db.query(itemsQuery, [...params, limit, offset]),
      this.db.query(countQuery, [userId]),
    ]);

    const counts = countRes.rows[0] || { total: 0, unread: 0 };

    return {
      notifications: itemsRes.rows,
      pagination: {
        limit,
        offset,
        total: counts.total,
        unread: counts.unread,
      },
    };
  }

  /**
   * Marks a specific notification as read.
   */
  async markAsRead(userId: string, notificationId: string) {
    const res = await this.db.query(`
      UPDATE user_notifications
      SET is_read = true, read_at = now()
      WHERE id = $1 AND user_id = $2
      RETURNING id, is_read, read_at
    `, [notificationId, userId]);

    if (!res.rowCount) {
      throw new NotFoundException({ code: 'NOTIFICATION_NOT_FOUND' });
    }

    return res.rows[0];
  }

  /**
   * Marks all unread notifications as read.
   */
  async markAllAsRead(userId: string) {
    const res = await this.db.query(`
      UPDATE user_notifications
      SET is_read = true, read_at = now()
      WHERE user_id = $1 AND is_read = false
      RETURNING id
    `, [userId]);

    return {
      success: true,
      markedCount: res.rowCount,
    };
  }

  /**
   * Retrieves notification preferences.
   */
  async getPreferences(userId: string) {
    const res = await this.db.query(`
      SELECT user_id, enable_push, enable_in_app, enable_sound,
             quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
             muted_categories, updated_at
      FROM notification_preferences
      WHERE user_id = $1
    `, [userId]);

    if (res.rowCount) {
      const row = res.rows[0];
      return {
        enablePush: row.enable_push,
        enableInApp: row.enable_in_app,
        enableSound: row.enable_sound,
        quietHoursEnabled: row.quiet_hours_enabled,
        quietHoursStart: row.quiet_hours_start,
        quietHoursEnd: row.quiet_hours_end,
        mutedCategories: row.muted_categories || [],
      };
    }

    // Default preferences
    return {
      enablePush: true,
      enableInApp: true,
      enableSound: true,
      quietHoursEnabled: false,
      quietHoursStart: null,
      quietHoursEnd: null,
      mutedCategories: [],
    };
  }

  /**
   * Updates notification preferences.
   */
  async updatePreferences(userId: string, dto: NotificationPreferencesDto) {
    const res = await this.db.query(`
      INSERT INTO notification_preferences (
        user_id, enable_push, enable_in_app, enable_sound,
        quiet_hours_enabled, quiet_hours_start, quiet_hours_end,
        muted_categories, updated_at
      )
      VALUES (
        $1,
        COALESCE($2, true),
        COALESCE($3, true),
        COALESCE($4, true),
        COALESCE($5, false),
        $6,
        $7,
        COALESCE($8::jsonb, '[]'::jsonb),
        now()
      )
      ON CONFLICT (user_id) DO UPDATE SET
        enable_push = COALESCE($2, notification_preferences.enable_push),
        enable_in_app = COALESCE($3, notification_preferences.enable_in_app),
        enable_sound = COALESCE($4, notification_preferences.enable_sound),
        quiet_hours_enabled = COALESCE($5, notification_preferences.quiet_hours_enabled),
        quiet_hours_start = CASE WHEN $6 IS NOT NULL THEN $6 ELSE notification_preferences.quiet_hours_start END,
        quiet_hours_end = CASE WHEN $7 IS NOT NULL THEN $7 ELSE notification_preferences.quiet_hours_end END,
        muted_categories = CASE WHEN $8 IS NOT NULL THEN $8::jsonb ELSE notification_preferences.muted_categories END,
        updated_at = now()
      RETURNING *
    `, [
      userId,
      dto.enablePush,
      dto.enableInApp,
      dto.enableSound,
      dto.quietHoursEnabled,
      dto.quietHoursStart,
      dto.quietHoursEnd,
      dto.mutedCategories ? JSON.stringify(dto.mutedCategories) : null,
    ]);

    const row = res.rows[0];
    return {
      enablePush: row.enable_push,
      enableInApp: row.enable_in_app,
      enableSound: row.enable_sound,
      quietHoursEnabled: row.quiet_hours_enabled,
      quietHoursStart: row.quiet_hours_start,
      quietHoursEnd: row.quiet_hours_end,
      mutedCategories: row.muted_categories || [],
    };
  }
}
