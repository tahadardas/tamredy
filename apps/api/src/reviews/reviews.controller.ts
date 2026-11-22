import { Body, Controller, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { NurseReportDto, ReviewDto } from '../common/dto.js';
import { ReviewsService } from './reviews.service.js';
@Controller('v1/visits') @UseGuards(AuthGuard)
export class ReviewsController {
  constructor(private readonly reviews:ReviewsService){}
  @Post(':id/patient-review') patient(@Request() r:AuthRequest,@Param('id') id:string,@Body() dto:ReviewDto){requireRole(r.user!,'PATIENT');return this.reviews.patientReview(r.user!.id,id,dto);}
  @Post(':id/nurse-report') nurse(@Request() r:AuthRequest,@Param('id') id:string,@Body() dto:NurseReportDto){requireRole(r.user!,'NURSE');return this.reviews.nurseReport(r.user!.id,id,dto);}
}
