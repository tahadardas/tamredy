import { Controller, Get, Post, UseGuards, Request, NotImplementedException } from '@nestjs/common';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
@Controller('v1/wallet') @UseGuards(AuthGuard)
export class WalletController {
  @Get('status')
  status(@Request() req:AuthRequest) { requireRole(req.user!,'PATIENT'); return {mode:'DISABLED',providerConnected:false,reason:'LICENSED_PAYMENT_PROVIDER_REQUIRED'}; }
  @Post('topups')
  topup(@Request() req:AuthRequest) {
    requireRole(req.user!,'PATIENT');
    throw new NotImplementedException({code:'WALLET_NOT_ENABLED',message:'Connect a legally licensed provider before accepting money'});
  }
}
