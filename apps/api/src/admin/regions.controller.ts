import { BadRequestException, Body, Controller, Get, Param, Patch, Post, Request, UseGuards } from '@nestjs/common';
import { IsBoolean, IsInt, IsNumber, IsOptional, IsString, IsUUID, Max, MaxLength, Min, MinLength } from 'class-validator';
import { AuthGuard, AuthRequest, requireAnyRole, requireRole } from '../auth/auth.guard.js';
import { DbService } from '../db/db.service.js';
import { conflict, missing } from '../common/errors.js';

class GovDto { @IsString() @MinLength(2) @MaxLength(60) nameAr!: string; @IsOptional() @IsInt() @Min(0) @Max(9999) sortOrder?: number; }
class GovPatchDto { @IsOptional() @IsString() @MinLength(2) @MaxLength(60) nameAr?: string; @IsOptional() @IsBoolean() active?: boolean; @IsOptional() @IsInt() @Min(0) @Max(9999) sortOrder?: number; }
class AreaDto extends GovDto { @IsUUID() governorateId!: string; @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number; @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number; }
class AreaPatchDto extends GovPatchDto { @IsOptional() @IsNumber() @Min(-90) @Max(90) lat?: number; @IsOptional() @IsNumber() @Min(-180) @Max(180) lng?: number; }

/** Public: the active governorates with their active areas (needed by the nurse sign-up screen before login). */
@Controller('v1/catalog')
export class RegionsPublicController {
  constructor(private readonly db: DbService) {}
  @Get('regions') async list() {
    const [g, a] = await Promise.all([
      this.db.query('SELECT id,name_ar FROM governorates WHERE active ORDER BY sort_order,name_ar'),
      this.db.query('SELECT id,governorate_id,name_ar,lat,lng FROM areas WHERE active ORDER BY sort_order,name_ar'),
    ]);
    return { governorates: g.rows.map((x: any) => ({ id: x.id, name: x.name_ar, areas: a.rows.filter((y: any) => y.governorate_id === x.id).map((y: any) => ({ id: y.id, name: y.name_ar, lat: y.lat === null ? null : Number(y.lat), lng: y.lng === null ? null : Number(y.lng) })) })) };
  }
}

/** Admin: add / rename / deactivate. Nothing is deleted (nurses reference these rows). */
@Controller('v1/admin/regions') @UseGuards(AuthGuard)
export class AdminRegionsController {
  constructor(private readonly db: DbService) {}
  private audit(c: { query: (s: string, p?: unknown[]) => Promise<any> }, actor: string, action: string, id: string, detail: unknown) {
    return c.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id,detail) VALUES($1,$2,'region',$3,$4::jsonb)`, [actor, action, id, JSON.stringify(detail)]);
  }

  @Get() async all(@Request() r: AuthRequest) {
    requireAnyRole(r.user!, ['ADMIN', 'CLINICAL_REVIEWER']);
    const [g, a] = await Promise.all([
      this.db.query(`SELECT g.id,g.name_ar,g.active,g.sort_order,(SELECT count(*)::int FROM nurses n WHERE n.governorate_id=g.id) AS nurses FROM governorates g ORDER BY g.sort_order,g.name_ar`),
      this.db.query(`SELECT a.id,a.governorate_id,a.name_ar,a.active,a.sort_order,a.lat,a.lng,(SELECT count(*)::int FROM nurses n WHERE n.area_id=a.id) AS nurses FROM areas a ORDER BY a.sort_order,a.name_ar`),
    ]);
    return { governorates: g.rows.map((x: any) => ({ ...x, areas: a.rows.filter((y: any) => y.governorate_id === x.id) })) };
  }

  @Post('governorates') async addGov(@Request() r: AuthRequest, @Body() d: GovDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      if ((await c.query('SELECT 1 FROM governorates WHERE name_ar=$1', [d.nameAr.trim()])).rowCount) conflict('REGION_EXISTS');
      const row = (await c.query('INSERT INTO governorates(name_ar,sort_order) VALUES($1,$2) RETURNING id', [d.nameAr.trim(), d.sortOrder ?? 100])).rows[0];
      await this.audit(c, r.user!.id, 'region.governorate_added', row.id, { name: d.nameAr });
      return { id: row.id };
    });
  }

  @Patch('governorates/:id') async editGov(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: GovPatchDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      if (d.nameAr && (await c.query('SELECT 1 FROM governorates WHERE name_ar=$1 AND id<>$2', [d.nameAr.trim(), id])).rowCount) conflict('REGION_EXISTS');
      const u = await c.query('UPDATE governorates SET name_ar=coalesce($2,name_ar),active=coalesce($3,active),sort_order=coalesce($4,sort_order) WHERE id=$1 RETURNING id', [id, d.nameAr?.trim() ?? null, d.active ?? null, d.sortOrder ?? null]);
      if (!u.rowCount) missing();
      await this.audit(c, r.user!.id, 'region.governorate_updated', id, d);
      return { id };
    });
  }

  @Post('areas') async addArea(@Request() r: AuthRequest, @Body() d: AreaDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      if (!(await c.query('SELECT 1 FROM governorates WHERE id=$1', [d.governorateId])).rowCount) missing();
      if ((await c.query('SELECT 1 FROM areas WHERE governorate_id=$1 AND name_ar=$2', [d.governorateId, d.nameAr.trim()])).rowCount) conflict('REGION_EXISTS');
      const row = (await c.query('INSERT INTO areas(governorate_id,name_ar,sort_order,lat,lng) VALUES($1,$2,$3,$4,$5) RETURNING id', [d.governorateId, d.nameAr.trim(), d.sortOrder ?? 100, d.lat ?? null, d.lng ?? null])).rows[0];
      await this.audit(c, r.user!.id, 'region.area_added', row.id, { name: d.nameAr });
      return { id: row.id };
    });
  }

  @Patch('areas/:id') async editArea(@Request() r: AuthRequest, @Param('id') id: string, @Body() d: AreaPatchDto) {
    requireRole(r.user!, 'ADMIN');
    return this.db.transaction(async c => {
      const cur = (await c.query('SELECT governorate_id FROM areas WHERE id=$1', [id])).rows[0];
      if (!cur) missing();
      if (d.nameAr && (await c.query('SELECT 1 FROM areas WHERE governorate_id=$1 AND name_ar=$2 AND id<>$3', [cur.governorate_id, d.nameAr.trim(), id])).rowCount) conflict('REGION_EXISTS');
      await c.query('UPDATE areas SET name_ar=coalesce($2,name_ar),active=coalesce($3,active),sort_order=coalesce($4,sort_order),lat=coalesce($5::numeric,lat),lng=coalesce($6::numeric,lng) WHERE id=$1', [id, d.nameAr?.trim() ?? null, d.active ?? null, d.sortOrder ?? null, d.lat ?? null, d.lng ?? null]);
      await this.audit(c, r.user!.id, 'region.area_updated', id, d);
      return { id };
    });
  }
}

/** Validates a (governorate, area) pair: both active, and the area belongs to the governorate. */
export async function checkRegion(c: { query: (s: string, p?: unknown[]) => Promise<any> }, governorateId?: string | null, areaId?: string | null) {
  if (!governorateId && !areaId) return;
  if (!governorateId) throw new BadRequestException({ code: 'REGION_INVALID' });
  const ok = areaId
    ? (await c.query('SELECT 1 FROM areas a JOIN governorates g ON g.id=a.governorate_id WHERE a.id=$1 AND g.id=$2 AND a.active AND g.active', [areaId, governorateId])).rowCount
    : (await c.query('SELECT 1 FROM governorates WHERE id=$1 AND active', [governorateId])).rowCount;
  if (!ok) throw new BadRequestException({ code: 'REGION_INVALID' });
}
