import { Injectable } from '@nestjs/common';
import { conflict, missing } from '../common/errors.js';
import { CheckinsRepository } from './checkins.repository.js';
import { SafetyRepository } from './safety.repository.js';
import type { SafetyCheckinResponseDto } from './safety.dto.js';

@Injectable()
export class CheckinsService {
  constructor(private readonly sessions: SafetyRepository, private readonly checkins: CheckinsRepository) {}

  async pending(owner: string, session: string) {
    return { checkin: await this.checkins.pending(owner, session) };
  }

  respond(owner: string, id: string, dto: SafetyCheckinResponseDto) {
    return this.sessions.transaction(async client => {
      const session = await this.sessions.session(client, owner, id);
      if (!session) missing();
      const saved = await this.checkins.response(client, id, dto.clientResponseId);
      if (saved) {
        if (saved.checkin_id !== dto.checkinId || saved.response !== dto.response) {
          conflict('CHECKIN_RESPONSE_ID_CONFLICT');
        }
        return saved;
      }
      const checkin = await this.checkins.current(client, id, dto.checkinId);
      if (!checkin) missing();
      if (session.checked_out_at || checkin.state !== 'PENDING' || !checkin.can_answer) {
        conflict('CHECKIN_NOT_OPEN');
      }
      if (dto.response === 'MORE_TIME') {
        if (checkin.snoozed_at) conflict('CHECKIN_ALREADY_EXTENDED');
        await this.checkins.extend(client, checkin.id, checkin.extension_seconds);
      } else {
        await this.checkins.finish(client, id, checkin.id, checkin.interval_seconds);
        if (dto.response === 'HELP' || dto.response === 'SAFE_EXIT') {
          await this.checkins.alert(client, id, checkin.id,
            dto.response === 'HELP' ? 'CHECKIN_HELP' : 'SAFE_EXIT_REQUESTED');
        }
      }
      return this.checkins.saveResponse(client, id, dto);
    });
  }
}
