import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';

export interface RecordItemOutcomeInput {
  status: 'COMPLETED' | 'SKIPPED' | 'CANCELLED';
  performedQuantity?: number;
  actualMinutes?: number;
  note?: string;
  reason?: string;
}

@Injectable()
export class RequestItemsService {
  constructor(private readonly db: DbService) {}

  async recordOutcome(nurseUserId: string, requestId: string, itemId: string, input: RecordItemOutcomeInput) {
    return this.db.transaction(client => this.recordOutcomeLocked(client,nurseUserId,requestId,itemId,input));
  }

  private async recordOutcomeLocked(
    client: PoolClient,
    nurseUserId: string,
    requestId: string,
    itemId: string,
    input: RecordItemOutcomeInput,
  ) {
    const item = (await client.query(`SELECT cri.id,cri.quantity,cri.item_status,cr.status AS request_status,
      a.id AS assignment_id,n.id AS nurse_id
      FROM care_request_items cri JOIN care_requests cr ON cr.id=cri.request_id
      JOIN request_assignments a ON a.request_id=cr.id AND a.status='ACTIVE'
      JOIN nurses n ON n.id=a.nurse_id
      WHERE cri.id=$1 AND cri.request_id=$2 AND n.user_id=$3 FOR UPDATE OF cri,cr,a`,
    [itemId,requestId,nurseUserId])).rows[0];
    if (!item) missing();
    if (item.request_status !== 'IN_SERVICE') conflict('REQUEST_NOT_IN_SERVICE');
    if (item.item_status !== 'PENDING') conflict('REQUEST_ITEM_ALREADY_FINALIZED');

    const note = input.note?.trim() || null;
    const reason = input.reason?.trim() || null;
    const performedQuantity = input.status === 'COMPLETED' ? input.performedQuantity : 0;
    if (input.status === 'COMPLETED') {
      if (!Number.isInteger(performedQuantity) || performedQuantity! < 1 || performedQuantity! > item.quantity) {
        conflict('INVALID_PERFORMED_QUANTITY');
      }
      if (!Number.isInteger(input.actualMinutes) || input.actualMinutes! < 1 || input.actualMinutes! > 1440) {
        conflict('INVALID_ACTUAL_MINUTES');
      }
      if (!note) conflict('COMPLETION_NOTE_REQUIRED');
    } else if (!reason) {
      conflict('ITEM_OUTCOME_REASON_REQUIRED');
    }

    const updated = (await client.query(`UPDATE care_request_items SET item_status=$2,
      performed_quantity=$3,actual_minutes=$4,completion_note=$5,status_reason=$6,
      completed_at=statement_timestamp() WHERE id=$1 RETURNING *`,
    [itemId,input.status,performedQuantity ?? 0,input.actualMinutes ?? null,note,reason])).rows[0];
    await client.query(`INSERT INTO request_events(request_id,actor_user_id,event_type,payload)
      VALUES($1,$2,'request.item.outcome',$3::jsonb)`, [requestId,nurseUserId,JSON.stringify({
      itemId,status:input.status,performedQuantity:performedQuantity ?? 0,actualMinutes:input.actualMinutes ?? null,reason,
    })]);
    return updated;
  }
}
