import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { ContactConsentDto, TrustedContactDto } from './trusted-contact.dto.js';
import { TrustedContactsService } from './trusted-contacts.service.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class TrustedContactsController {
  constructor(private readonly service: TrustedContactsService) {}

  @Get('me/trusted-contacts') list(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['PATIENT','NURSE']);
    return this.service.list(req.user!.id);
  }

  @Post('me/trusted-contacts') create(@Request() req: AuthRequest, @Body() dto: TrustedContactDto) {
    requireAnyRole(req.user!, ['PATIENT','NURSE']);
    return this.service.save(req.user!.id,dto);
  }

  @Put('me/trusted-contacts/:id') update(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: TrustedContactDto) {
    requireAnyRole(req.user!, ['PATIENT','NURSE']);
    return this.service.save(req.user!.id,dto,id);
  }

  @Delete('me/trusted-contacts/:id') remove(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['PATIENT','NURSE']);
    return this.service.remove(req.user!.id,id);
  }

  @Post('admin/safety/trusted-contacts/:id/consent')
  consent(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: ContactConsentDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.consent(req.user!.id,id,dto);
  }
}
