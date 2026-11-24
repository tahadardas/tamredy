import { Body, Controller, Get, HttpCode, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { IsIn, IsNumber, IsOptional, IsString, IsUUID, MaxLength, Min } from 'class-validator';
import { AuthGuard, AuthRequest } from '../auth/auth.guard.js';
import { ChatService } from './chat.service.js';

class SendMessageDto {
  @IsString()
  @MaxLength(4000)
  content!: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  clientMessageId?: string;

  @IsOptional()
  @IsIn(['TEXT', 'IMAGE', 'PDF', 'DOCUMENT', 'LOCATION', 'VOICE_NOTE'])
  messageType?: 'TEXT' | 'IMAGE' | 'PDF' | 'DOCUMENT' | 'LOCATION' | 'VOICE_NOTE';

  @IsOptional()
  @IsString()
  @MaxLength(500)
  attachmentUrl?: string;

  @IsOptional()
  attachmentMeta?: Record<string, unknown>;

  @IsOptional()
  @IsUUID()
  replyToMessageId?: string;
}

class MarkReadDto {
  @IsUUID()
  messageId!: string;
}

class AttachmentMetadataDto {
  @IsString()
  @MaxLength(255)
  filename!: string;

  @IsString()
  @MaxLength(100)
  mimeType!: string;

  @IsNumber()
  @Min(1)
  sizeBytes!: number;

  @IsOptional()
  isPrescription?: boolean;
}

@Controller('v1/conversations')
@UseGuards(AuthGuard)
export class ChatController {
  constructor(private readonly chat: ChatService) {}

  @Get()
  async list(@Request() r: AuthRequest) {
    return this.chat.listUserConversations(r.user!.id);
  }

  @Post('visit/:requestId')
  async openVisitConversation(
    @Request() r: AuthRequest,
    @Param('requestId') requestId: string,
  ) {
    return this.chat.getOrCreateVisitConversation(requestId, r.user!.id);
  }

  @Get(':id/messages')
  async messages(
    @Request() r: AuthRequest,
    @Param('id') conversationId: string,
    @Query('limit') limit?: string,
    @Query('before') before?: string,
  ) {
    const numLimit = limit ? parseInt(limit, 10) : 50;
    return this.chat.getMessages(r.user!.id, conversationId, numLimit, before);
  }

  @Post(':id/messages')
  @HttpCode(201)
  async sendMessage(
    @Request() r: AuthRequest,
    @Param('id') conversationId: string,
    @Body() body: SendMessageDto,
  ) {
    return this.chat.sendMessage(r.user!.id, conversationId, body);
  }

  @Post(':id/read')
  @HttpCode(200)
  async markRead(
    @Request() r: AuthRequest,
    @Param('id') conversationId: string,
    @Body() body: MarkReadDto,
  ) {
    return this.chat.markRead(r.user!.id, conversationId, body.messageId);
  }

  @Post(':id/attachments')
  @HttpCode(201)
  async uploadAttachment(
    @Request() r: AuthRequest,
    @Param('id') conversationId: string,
    @Body() body: AttachmentMetadataDto,
  ) {
    await this.chat.assertMembership(r.user!.id, conversationId);

    // Validate size (max 10MB)
    if (body.sizeBytes > 10 * 1024 * 1024) {
      throw new Error('ATTACHMENT_TOO_LARGE: Max 10MB allowed');
    }

    // Ban executables and unsafe types
    const allowedMime = [
      'image/jpeg', 'image/png', 'image/webp',
      'application/pdf', 'application/msword',
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ];

    if (!allowedMime.includes(body.mimeType)) {
      throw new Error('UNSUPPORTED_MIME_TYPE: Only medical documents, PDFs, and images are permitted');
    }

    // Generate secure opaque storage token
    const storageKey = `att_${Date.now()}_${Math.random().toString(36).slice(2, 10)}`;
    const authorizedDownloadUrl = `/v1/attachments/${storageKey}`;

    return {
      storageKey,
      authorizedDownloadUrl,
      isPrescription: Boolean(body.isPrescription),
    };
  }
}
