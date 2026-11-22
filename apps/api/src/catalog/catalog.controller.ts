import { Controller, Get, Request, UseGuards } from '@nestjs/common';
import { DbService } from '../db/db.service.js';
import { AuthGuard, AuthRequest, requireRole } from '../auth/auth.guard.js';
import { ReferenceCacheService } from '../cache/reference-cache.service.js';
@Controller('v1') @UseGuards(AuthGuard)
export class CatalogController {
 constructor(private readonly db:DbService,private readonly cache:ReferenceCacheService){}
 @Get('services') async services(){return this.cache.getOrLoad('services:public',async()=>
   (await this.db.query(`SELECT id,code,title_ar,description_ar,price_amount,currency_code,included_minutes,block_minutes,block_price,expected_minutes FROM services
   WHERE active=true AND dispatch_approved=true AND requires_prescription=false ORDER BY sort_order,title_ar,id`)).rows,300);}
 @Get('beneficiaries/mine') async beneficiaries(@Request() r:AuthRequest){requireRole(r.user!,'PATIENT');return (await this.db.query(`SELECT id,display_name FROM beneficiaries WHERE owner_user_id=$1 AND consent_status='GRANTED' ORDER BY created_at DESC`,[r.user!.id])).rows;}
}
