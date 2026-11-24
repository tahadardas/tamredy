import { Body, Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsObject, IsOptional, IsString, IsUUID, MaxLength } from 'class-validator';
import { AuthGuard, AuthRequest } from '../auth/auth.guard.js';
import { VoiceService } from './voice.service.js';

class InitiateCallInputDto {
  @IsUUID()
  requestId!: string;
}

class CallSignalInputDto {
  @IsIn(['SDP_OFFER', 'SDP_ANSWER', 'ICE_CANDIDATE'])
  eventType!: 'SDP_OFFER' | 'SDP_ANSWER' | 'ICE_CANDIDATE';

  @IsObject()
  data!: Record<string, unknown>;
}

class EndCallInputDto {
  @IsOptional()
  @IsString()
  @MaxLength(100)
  reason?: string;
}

@Controller('v1/calls')
@UseGuards(AuthGuard)
export class VoiceController {
  constructor(private readonly voice: VoiceService) {}

  @Post('initiate')
  @HttpCode(201)
  async initiate(
    @Request() r: AuthRequest,
    @Body() body: InitiateCallInputDto,
  ) {
    return this.voice.initiateCall(r.user!.id, body.requestId);
  }

  @Post(':id/accept')
  @HttpCode(200)
  async accept(
    @Request() r: AuthRequest,
    @Param('id') callId: string,
  ) {
    return this.voice.acceptCall(r.user!.id, callId);
  }

  @Post(':id/reject')
  @HttpCode(200)
  async reject(
    @Request() r: AuthRequest,
    @Param('id') callId: string,
    @Body() body: EndCallInputDto,
  ) {
    return this.voice.rejectCall(r.user!.id, callId, body.reason);
  }

  @Post(':id/end')
  @HttpCode(200)
  async end(
    @Request() r: AuthRequest,
    @Param('id') callId: string,
    @Body() body: EndCallInputDto,
  ) {
    return this.voice.endCall(r.user!.id, callId, body.reason);
  }

  @Post(':id/signal')
  @HttpCode(200)
  async signal(
    @Request() r: AuthRequest,
    @Param('id') callId: string,
    @Body() body: CallSignalInputDto,
  ) {
    return this.voice.relaySignal(r.user!.id, callId, body);
  }

  @Get(':id')
  async getCall(
    @Request() r: AuthRequest,
    @Param('id') callId: string,
  ) {
    return this.voice.getCall(r.user!.id, callId);
  }
}
