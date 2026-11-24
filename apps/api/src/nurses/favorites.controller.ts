import { Controller, Delete, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { FavoritesService } from './favorites.service.js';

@Controller('v1/favorites/nurses')
@UseGuards(AuthGuard)
export class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get()
  async list(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    return this.favorites.listFavorites(r.user!.id);
  }

  @Post(':id')
  @HttpCode(201)
  async add(
    @Request() r: AuthRequest,
    @Param('id') nurseId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.favorites.addFavorite(r.user!.id, nurseId);
  }

  @Delete(':id')
  @HttpCode(200)
  async remove(
    @Request() r: AuthRequest,
    @Param('id') nurseId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.favorites.removeFavorite(r.user!.id, nurseId);
  }
}
