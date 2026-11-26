import { randomUUID } from 'node:crypto';
import { Injectable, ForbiddenException, NotFoundException, BadRequestException } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { LiveGateway } from '../realtime/live.gateway.js';
import { inspectMessageForContactInfo } from './phone-shield.js';
import { buildNotificationPayload } from '../notifications/notification-routing.js';

export interface SendChatMessageDto {
  clientMessageId?: string;
  content: string;
  messageType?: 'TEXT' | 'IMAGE' | 'PDF' | 'DOCUMENT' | 'LOCATION' | 'SYSTEM_MESSAGE' | 'VOICE_NOTE';
  attachmentUrl?: string;
  attachmentMeta?: Record<string, unknown>;
  replyToMessageId?: string;
}

@Injectable()
export class ChatService {
  constructor(
    private readonly db: DbService,
    private readonly live: LiveGateway,
  ) {}

  /** Ensures user is a member of the conversation */
  async assertMembership(userId: string, conversationId: string): Promise<{ role: string }> {
    const res = await this.db.query(
      `SELECT role FROM conversation_members WHERE conversation_id = $1 AND user_id = $2`,
      [conversationId, userId],
    );
    if (!res.rowCount) {
      throw new ForbiddenException({ code: 'NOT_CONVERSATION_MEMBER' });
    }
    return { role: res.rows[0].role };
  }

  /** Finds or creates conversation for an active/confirmed care request */
  async getOrCreateVisitConversation(requestId: string, requestingUserId: string) {
    const reqRes = await this.db.query(
      `SELECT cr.id, cr.requester_user_id, a.nurse_id, n.user_id AS nurse_user_id
       FROM care_requests cr
       LEFT JOIN request_assignments a ON a.request_id = cr.id AND a.status IN ('ACTIVE', 'COMPLETED')
       LEFT JOIN nurses n ON n.id = a.nurse_id
       WHERE cr.id = $1`,
      [requestId],
    );

    if (!reqRes.rowCount) throw new NotFoundException({ code: 'REQUEST_NOT_FOUND' });
    const req = reqRes.rows[0];

    // Authorization: only the patient or the assigned nurse can access
    const isPatient = req.requester_user_id === requestingUserId;
    const isNurse = req.nurse_user_id === requestingUserId;
    if (!isPatient && !isNurse) {
      throw new ForbiddenException({ code: 'UNAUTHORIZED_FOR_VISIT_CHAT' });
    }

    if (!req.nurse_user_id) {
      throw new BadRequestException({ code: 'NO_ASSIGNED_NURSE_YET' });
    }

    return this.db.transaction(async client => {
      // Find existing
      const existing = await client.query(
        `SELECT id, request_id, type, status, created_at FROM conversations WHERE request_id = $1 AND type = 'VISIT'`,
        [requestId],
      );

      if (existing.rowCount) {
        return existing.rows[0];
      }

      // Create new conversation
      const convRes = await client.query(
        `INSERT INTO conversations(request_id, type, status) VALUES($1, 'VISIT', 'ACTIVE') RETURNING *`,
        [requestId],
      );
      const conv = convRes.rows[0];

      // Add patient member
      await client.query(
        `INSERT INTO conversation_members(conversation_id, user_id, role) VALUES($1, $2, 'PATIENT') ON CONFLICT DO NOTHING`,
        [conv.id, req.requester_user_id],
      );

      // Add nurse member
      await client.query(
        `INSERT INTO conversation_members(conversation_id, user_id, role) VALUES($1, $2, 'NURSE') ON CONFLICT DO NOTHING`,
        [conv.id, req.nurse_user_id],
      );

      return conv;
    });
  }

  /** Lists conversations for user with last message and unread count */
  async listUserConversations(userId: string) {
    const res = await this.db.query(`
      SELECT c.id, c.request_id, c.type, c.status, c.created_at,
             cm.role AS my_role, cm.last_read_at,
             (
               SELECT count(*)::int FROM chat_messages m
               WHERE m.conversation_id = c.id
                 AND (cm.last_read_at IS NULL OR m.created_at > cm.last_read_at)
                 AND (m.sender_user_id IS NULL OR m.sender_user_id <> $1)
             ) AS unread_count,
             (
               SELECT jsonb_build_object(
                 'id', m.id, 'content', m.content, 'messageType', m.message_type,
                 'createdAt', m.created_at, 'senderUserId', m.sender_user_id
               )
               FROM chat_messages m
               WHERE m.conversation_id = c.id
               ORDER BY m.created_at DESC LIMIT 1
             ) AS last_message,
             (
               SELECT jsonb_agg(jsonb_build_object(
                 'userId', u.id, 'role', m2.role, 'displayName', u.display_name
               ))
               FROM conversation_members m2
               JOIN users u ON u.id = m2.user_id
               WHERE m2.conversation_id = c.id AND m2.user_id <> $1
             ) AS participants
      FROM conversation_members cm
      JOIN conversations c ON c.id = cm.conversation_id
      WHERE cm.user_id = $1
      ORDER BY c.created_at DESC
    `, [userId]);

    return res.rows;
  }

  /** Paginated message history */
  async getMessages(userId: string, conversationId: string, limit = 50, beforeId?: string) {
    await this.assertMembership(userId, conversationId);
    const clampedLimit = Math.min(Math.max(1, limit), 100);

    let query = `
      SELECT m.id, m.conversation_id, m.sender_user_id, m.client_message_id,
             m.message_type, m.content, m.attachment_url, m.attachment_meta,
             m.reply_to_message_id, m.status, m.has_contact_advisory, m.created_at,
             u.role AS sender_role
      FROM chat_messages m
      LEFT JOIN users u ON u.id = m.sender_user_id
      WHERE m.conversation_id = $1
    `;
    const params: unknown[] = [conversationId];

    if (beforeId) {
      params.push(beforeId);
      query += ` AND m.created_at < (SELECT created_at FROM chat_messages WHERE id = $2)`;
      params.push(clampedLimit);
      query += ` ORDER BY m.created_at DESC LIMIT $3`;
    } else {
      params.push(clampedLimit);
      query += ` ORDER BY m.created_at DESC LIMIT $2`;
    }

    const res = await this.db.query(query, params);
    return res.rows.reverse(); // Chronological order
  }

  /** Sends an authenticated message */
  async sendMessage(userId: string, conversationId: string, dto: SendChatMessageDto) {
    await this.assertMembership(userId, conversationId);

    const content = dto.content.trim();
    if (!content && !dto.attachmentUrl) {
      throw new BadRequestException({ code: 'EMPTY_MESSAGE' });
    }

    // Contact advisory inspection
    const shieldResult = inspectMessageForContactInfo(content);

    return this.db.transaction(async client => {
      // Idempotency check with client_message_id
      if (dto.clientMessageId) {
        const existing = await client.query(
          `SELECT * FROM chat_messages WHERE conversation_id = $1 AND client_message_id = $2`,
          [conversationId, dto.clientMessageId],
        );
        if (existing.rowCount) {
          return { ...existing.rows[0], replayed: true, advisory: shieldResult.advisoryMessage };
        }
      }

      const res = await client.query(
        `INSERT INTO chat_messages(
           conversation_id, sender_user_id, client_message_id, message_type,
           content, attachment_url, attachment_meta, reply_to_message_id,
           status, has_contact_advisory
         )
         VALUES($1, $2, $3, coalesce($4, 'TEXT'), $5, $6, coalesce($7, '{}')::jsonb, $8, 'STORED', $9)
         RETURNING *`,
        [
          conversationId,
          userId,
          dto.clientMessageId ?? null,
          dto.messageType ?? 'TEXT',
          content,
          dto.attachmentUrl ?? null,
          dto.attachmentMeta ? JSON.stringify(dto.attachmentMeta) : null,
          dto.replyToMessageId ?? null,
          shieldResult.hasContactLeak,
        ],
      );

      const message = res.rows[0];

      // Find other recipients in conversation (with role for strict routing)
      const otherMembers = await client.query(
        `SELECT cm.user_id, u.role FROM conversation_members cm JOIN users u ON u.id = cm.user_id
         WHERE cm.conversation_id = $1 AND cm.user_id <> $2`,
        [conversationId, userId],
      );

      // Realtime dispatch + Outbox push using the exact same eventId for deduplication
      for (const recipient of otherMembers.rows) {
        const recipientRole = recipient.role === 'NURSE' ? 'NURSE' : 'PATIENT';
        const targetApp = recipientRole === 'NURSE' ? 'NURSE_APP' : 'PATIENT_APP';
        const sharedEventId = randomUUID();
        const payload = buildNotificationPayload({
          eventId: sharedEventId,
          eventType: 'chat.message',
          recipientUserId: recipient.user_id,
          recipientRole,
          targetApp,
          conversationId,
          extra: {
            messageId: message.id,
            senderUserId: userId,
            snippet: content.slice(0, 100),
          },
        });

        await this.live.sendToUser(recipient.user_id, 'chat.message', {
          ...payload,
          conversationId,
          message,
        });

        // Outbox event for push notification (realtime already sent with matching eventId)
        await client.query(
          `INSERT INTO outbox_events(event_type, aggregate_id, payload, realtime_published_at)
           VALUES('chat.message', $1, $2::jsonb, now())`,
          [conversationId, JSON.stringify(payload)],
        );
      }

      return {
        ...message,
        replayed: false,
        hasContactAdvisory: shieldResult.hasContactLeak,
        advisoryMessage: shieldResult.advisoryMessage,
      };
    });
  }

  /** Marks messages read up to a specific messageId */
  async markRead(userId: string, conversationId: string, messageId: string) {
    await this.assertMembership(userId, conversationId);

    await this.db.transaction(async client => {
      await client.query(
        `UPDATE conversation_members
         SET last_read_message_id = $3, last_read_at = now()
         WHERE conversation_id = $1 AND user_id = $2`,
        [conversationId, userId, messageId],
      );

      // Emit read receipt to other participants
      const otherMembers = await client.query(
        `SELECT user_id FROM conversation_members WHERE conversation_id = $1 AND user_id <> $2`,
        [conversationId, userId],
      );

      for (const m of otherMembers.rows) {
        await this.live.sendToUser(m.user_id, 'chat.read', {
          conversationId,
          readByUserId: userId,
          lastReadMessageId: messageId,
          readAt: new Date().toISOString(),
        });
      }
    });

    return { ok: true };
  }

  /** Sends system message into conversation on visit lifecycle change */
  async sendSystemMessage(conversationId: string, text: string) {
    const res = await this.db.query(
      `INSERT INTO chat_messages(conversation_id, sender_user_id, message_type, content, status)
       VALUES($1, NULL, 'SYSTEM_MESSAGE', $2, 'STORED') RETURNING *`,
      [conversationId, text],
    );
    const msg = res.rows[0];

    const members = await this.db.query(
      `SELECT user_id FROM conversation_members WHERE conversation_id = $1`,
      [conversationId],
    );

    for (const m of members.rows) {
      await this.live.sendToUser(m.user_id, 'chat.message', {
        conversationId,
        message: msg,
      });
    }

    return msg;
  }
}
