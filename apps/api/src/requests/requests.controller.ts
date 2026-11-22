import { Body, Controller, Get, Headers, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { CreateRequestDto } from '../common/dto.js';
import { RequestsService } from './requests.service.js';
import { validatedPage } from '../common/page-query.js';
@Controller('v1/requests') @UseGuards(AuthGuard)
export class RequestsController {
  constructor(private readonly service:RequestsService) {}
  @Post()
  create(@Request() r:AuthRequest,@Body() body:CreateRequestDto,@Headers('idempotency-key') key:string) {
    requireRole(r.user!,'PATIENT');return this.service.create(r.user!.id,body,key);
  }
  @Get('mine') list(@Request() r:AuthRequest,@Query('limit') limit?:string,@Query('cursor') cursor?:string){requireRole(r.user!,'PATIENT');return this.service.list(r.user!.id,validatedPage(limit,cursor,`patient:${r.user!.id}`));}
  @Get(':id') details(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'PATIENT');return this.service.findOne(r.user!.id,id);}
  @Get(':id/tracking') track(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'PATIENT');return this.service.track(r.user!.id,id);}
  @Post(':id/cancel') cancel(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'PATIENT');return this.service.cancel(r.user!.id,id);}
}
