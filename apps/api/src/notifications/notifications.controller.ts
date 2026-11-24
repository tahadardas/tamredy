import { Body, Controller, Get, HttpCode, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { IsArray, IsBoolean, IsOptional, IsString } from 'class-validator';
import { AuthGuard, AuthRequest } from '../auth/auth.guard.js';
import { NotificationsService, NotificationPreferencesDto } from './notifications.service.js';

class UpdatePreferencesInputDto implements NotificationPreferencesDto {
  @IsOptional()
  @IsBoolean()
  enablePush?: boolean;

  @IsOptional()
  @IsBoolean()
  enableInApp?: boolean;

  @IsOptional()
  @IsBoolean()
  enableSound?: boolean;

  @IsOptional()
  @IsBoolean()
  quietHoursEnabled?: boolean;

  @IsOptional()
  @IsString()
  quietHoursStart?: string | null;

  @IsOptional()
  @IsString()
  quietHoursEnd?: string | null;

  @IsOptional()
  @IsArray()
  mutedCategories?: string[];
}

@Controller('v1/notifications')
@UseGuards(AuthGuard)
export class NotificationsController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  async list(
    @Request() r: AuthRequest,
    @Query('limit') limit?: string,
    @Query('offset') offset?: string,
    @Query('unreadOnly') unreadOnly?: string,
  ) {
    return this.notifications.listNotifications(r.user!.id, {
      limit: limit ? parseInt(limit, 10) : undefined,
      offset: offset ? parseInt(offset, 10) : undefined,
      unreadOnly: unreadOnly === 'true',
    });
  }

  @Post(':id/read')
  @HttpCode(200)
  async markAsRead(
    @Request() r: AuthRequest,
    @Param('id') id: string,
  ) {
    return this.notifications.markAsRead(r.user!.id, id);
  }

  @Post('read-all')
  @HttpCode(200)
  async markAllAsRead(@Request() r: AuthRequest) {
    return this.notifications.markAllAsRead(r.user!.id);
  }

  @Get('preferences')
  async getPreferences(@Request() r: AuthRequest) {
    return this.notifications.getPreferences(r.user!.id);
  }

  @Put('preferences')
  async updatePreferences(
    @Request() r: AuthRequest,
    @Body() body: UpdatePreferencesInputDto,
  ) {
    return this.notifications.updatePreferences(r.user!.id, body);
  }
}
