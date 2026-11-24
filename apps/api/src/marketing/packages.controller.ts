import { Controller, Get, HttpCode, Param, Post, Request, UseGuards } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { PackagesService } from './packages.service.js';

@Controller('v1/packages')
export class PackagesController {
  constructor(private readonly packages: PackagesService) {}

  @Get()
  async list() {
    return this.packages.listPackages();
  }

  @Get('mine')
  @UseGuards(AuthGuard)
  async listMine(@Request() r: AuthRequest) {
    requireRole(r.user!, 'PATIENT');
    return this.packages.getUserPackages(r.user!.id);
  }

  @Post(':id/purchase')
  @UseGuards(AuthGuard)
  @HttpCode(201)
  async purchase(
    @Request() r: AuthRequest,
    @Param('id') packageId: string,
  ) {
    requireRole(r.user!, 'PATIENT');
    return this.packages.purchasePackage(r.user!.id, packageId);
  }
}
