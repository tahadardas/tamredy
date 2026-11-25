import { Body, Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { IsBoolean, IsIn, IsInt, IsNumber, IsObject, IsOptional, IsString, IsUUID, Max, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest } from '../auth/auth.guard.js';
import { VoiceService } from './voice.service.js';

class InitiateCallInputDto {
  @IsUUID()
  requestId!: string;

  @IsOptional()
  @IsUUID()
  idempotencyKey?: string;
}

class CallSignalInputDto {
  @IsUUID()
  eventId!: string;

  @IsInt()
  @Min(1)
  sequenceNumber!: number;

  @IsIn(['SDP_OFFER', 'SDP_ANSWER', 'ICE_CANDIDATE', 'ICE_RESTART'])
  eventType!: 'SDP_OFFER' | 'SDP_ANSWER' | 'ICE_CANDIDATE' | 'ICE_RESTART';

  @IsObject()
  data!: Record<string, unknown>;
}

class CallQualityInputDto {
  @IsOptional() @IsNumber() @Min(0) @Max(60000) rttMs?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(60000) jitterMs?: number;
  @IsOptional() @IsNumber() @Min(0) @Max(100) packetLossPercent?: number;
  @IsOptional() @IsNumber() @Min(0) bitrateKbps?: number;
  @IsOptional() @IsString() @MaxLength(30) candidateType?: string;
  @IsOptional() @IsString() @MaxLength(30) connectionType?: string;
  @IsOptional() @IsBoolean() turnUsed?: boolean;
  @IsOptional() @IsInt() @Min(0) @Max(100) reconnectionCount?: number;
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
    return this.voice.initiateCall(r.user!.id, body.requestId, body.idempotencyKey);
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

  @Post(':id/connected')
  @HttpCode(200)
  connected(@Request() r: AuthRequest, @Param('id') callId: string) {
    return this.voice.markConnected(r.user!.id, callId);
  }

  @Get('active/mine')
  active(@Request() r: AuthRequest) {
    return this.voice.activeCalls(r.user!.id);
  }

  @Post(':id/quality')
  @HttpCode(202)
  quality(@Request() r: AuthRequest, @Param('id') callId: string, @Body() body: CallQualityInputDto) {
    return this.voice.recordQuality(r.user!.id, callId, body);
  }
}
