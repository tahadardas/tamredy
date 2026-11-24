import { Body, Controller, Delete, Get, Param, ParseUUIDPipe, Post, Put, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { SavedPlaceDto } from './saved-place.dto.js';
import { SavedPlacesService } from './saved-places.service.js';

@Controller('v1/patient/saved-places')
@UseGuards(AuthGuard)
export class SavedPlacesController {
  constructor(private readonly service: SavedPlacesService) {}

  @Get() list(@Request() request: AuthRequest) {
    requireRole(request.user!, 'PATIENT');
    return this.service.list(request.user!.id);
  }

  @Post() create(@Request() request: AuthRequest, @Body() dto: SavedPlaceDto) {
    requireRole(request.user!, 'PATIENT');
    return this.service.save(request.user!.id, dto);
  }

  @Put(':id') update(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string, @Body() dto: SavedPlaceDto) {
    requireRole(request.user!, 'PATIENT');
    return this.service.save(request.user!.id, dto, id);
  }

  @Delete(':id') remove(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(request.user!, 'PATIENT');
    return this.service.remove(request.user!.id, id);
  }

  @Post(':id/use') use(@Request() request: AuthRequest, @Param('id', ParseUUIDPipe) id: string) {
    requireRole(request.user!, 'PATIENT');
    return this.service.use(request.user!.id, id);
  }
}
