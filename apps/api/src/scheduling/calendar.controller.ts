import { Body, Controller, Delete, Get, HttpCode, Param, Post, Query, Request, UseGuards } from '@nestjs/common';
import { IsISO8601, IsOptional, IsString, MaxLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { NurseCalendarService } from './calendar.service.js';

class AddCalendarBlockDto {
  @IsISO8601()
  startTime!: string;

  @IsISO8601()
  endTime!: string;

  @IsOptional()
  @IsString()
  @MaxLength(100)
  reason?: string;
}

@Controller('v1/nurse-calendar')
@UseGuards(AuthGuard)
export class NurseCalendarController {
  constructor(private readonly calendar: NurseCalendarService) {}

  @Get()
  async getSchedule(
    @Request() r: AuthRequest,
    @Query('from') fromDate?: string,
    @Query('to') toDate?: string,
  ) {
    requireRole(r.user!, 'NURSE');
    const now = new Date();
    const from = fromDate ?? new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();
    const to = toDate ?? new Date(now.getTime() + 14 * 24 * 60 * 60 * 1000).toISOString();
    return this.calendar.getSchedule(r.user!.id, from, to);
  }

  @Post('blocks')
  @HttpCode(201)
  async addBlock(
    @Request() r: AuthRequest,
    @Body() body: AddCalendarBlockDto,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.calendar.addBlock(r.user!.id, body);
  }

  @Delete('blocks/:id')
  @HttpCode(200)
  async removeBlock(
    @Request() r: AuthRequest,
    @Param('id') blockId: string,
  ) {
    requireRole(r.user!, 'NURSE');
    return this.calendar.removeBlock(r.user!.id, blockId);
  }
}
