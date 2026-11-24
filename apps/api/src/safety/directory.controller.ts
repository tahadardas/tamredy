import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireAnyRole } from '../auth/auth.guard.js';
import { DirectoryEntryDto } from './directory.dto.js';
import { DirectoryService } from './directory.service.js';

@Controller('v1')
@UseGuards(AuthGuard)
export class DirectoryController {
  constructor(private readonly service: DirectoryService) {}

  @Get('safety/directory') visible(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['PATIENT','NURSE']);
    return this.service.visible();
  }

  @Get('admin/safety/directory') list(@Request() req: AuthRequest) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.list(req.user!.id);
  }

  @Post('admin/safety/directory') create(@Request() req: AuthRequest, @Body() dto: DirectoryEntryDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.save(req.user!.id,dto);
  }

  @Put('admin/safety/directory/:id') edit(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: DirectoryEntryDto) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.save(req.user!.id,dto,id);
  }

  @Delete('admin/safety/directory/:id') deactivate(@Request() req: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireAnyRole(req.user!, ['ADMIN','CLINICAL_REVIEWER']);
    return this.service.deactivate(req.user!.id,id);
  }
}
