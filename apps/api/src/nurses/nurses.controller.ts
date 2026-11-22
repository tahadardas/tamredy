import { Body, Controller, Get, Param, Post, Put, Query, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { AvailabilityDto, LocationDto } from '../common/dto.js';
import { NursesService } from './nurses.service.js';
import { DispatchService } from '../dispatch/dispatch.service.js';
import { validatedPage } from '../common/page-query.js';
@Controller('v1/nurse') @UseGuards(AuthGuard)
export class NursesController {
  constructor(private readonly nurses:NursesService,private readonly dispatch:DispatchService) {}
  @Put('me/availability') availability(@Request() r:AuthRequest,@Body() dto:AvailabilityDto){requireRole(r.user!,'NURSE');return this.nurses.availability(r.user!.id,dto);}
  @Put('me/location') location(@Request() r:AuthRequest,@Body() dto:LocationDto){requireRole(r.user!,'NURSE');return this.nurses.location(r.user!.id,dto);}
  @Post('me/heartbeat') heartbeat(@Request() r:AuthRequest){requireRole(r.user!,'NURSE');return this.nurses.heartbeat(r.user!.id);}
  @Get('me/history') history(@Request() r:AuthRequest,@Query('limit') limit?:string,@Query('cursor') cursor?:string){requireRole(r.user!,'NURSE');return this.nurses.history(r.user!.id,validatedPage(limit,cursor,`nurse:${r.user!.id}`));}
  @Get('me/offers') offers(@Request() r:AuthRequest){requireRole(r.user!,'NURSE');return this.dispatch.offersForUser(r.user!.id);}
  @Post('offers/:offerId/accept') accept(@Request() r:AuthRequest,@Param('offerId') id:string){requireRole(r.user!,'NURSE');return this.dispatch.accept(r.user!.id,id);}
  @Post('offers/:offerId/decline') decline(@Request() r:AuthRequest,@Param('offerId') id:string){requireRole(r.user!,'NURSE');return this.dispatch.decline(r.user!.id,id);}
  @Get('assignments/:id') details(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'NURSE');return this.nurses.assignmentDetails(r.user!.id,id);}
  @Post('assignments/:id/depart') depart(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'NURSE');return this.dispatch.transition(r.user!.id,id,'depart');}
  @Post('assignments/:id/arrive') arrive(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'NURSE');return this.dispatch.transition(r.user!.id,id,'arrive');}
  @Post('assignments/:id/start') start(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'NURSE');return this.dispatch.transition(r.user!.id,id,'start');}
  @Post('assignments/:id/complete') complete(@Request() r:AuthRequest,@Param('id') id:string){requireRole(r.user!,'NURSE');return this.dispatch.transition(r.user!.id,id,'complete');}
}
