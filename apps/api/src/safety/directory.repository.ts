import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { DirectoryEntryDto } from './directory.dto.js';

@Injectable()
export class DirectoryRepository {
  constructor(private readonly db: DbService) {}

  transaction<T>(work: (client: PoolClient) => Promise<T>) { return this.db.transaction(work); }

  async visible() {
    return (await this.db.query(`SELECT id,name,category,governorate,area,dial_number,hours,official_source,
      verified_at,valid_until FROM emergency_directory WHERE active AND valid_until>now()
      ORDER BY governorate NULLS FIRST,area NULLS FIRST,category,name,id LIMIT 200`)).rows;
  }

  async list(client: PoolClient) {
    return (await client.query('SELECT * FROM emergency_directory ORDER BY updated_at DESC,id LIMIT 200')).rows;
  }

  async save(client: PoolClient, actor: string, dto: DirectoryEntryDto, id?: string) {
    const values = [dto.name,dto.category,dto.governorate ?? null,dto.area ?? null,
      dto.dialNumber,dto.hours ?? null,dto.officialSource,dto.publishVerified,actor];
    const verifyAt = 'CASE WHEN $8::boolean THEN now() END';
    const verifiedBy = 'CASE WHEN $8::boolean THEN $9::uuid END';
    const validUntil = "CASE WHEN $8::boolean THEN now()+interval '90 days' END";
    const result = id
      ? await client.query(`UPDATE emergency_directory SET name=$1,category=$2,governorate=$3,area=$4,
        dial_number=$5,hours=$6,official_source=$7,active=$8,verified_by=${verifiedBy},
        verified_at=${verifyAt},valid_until=${validUntil},updated_at=now() WHERE id=$10 RETURNING *`, [...values,id])
      : await client.query(`INSERT INTO emergency_directory(name,category,governorate,area,dial_number,
        hours,official_source,active,verified_by,verified_at,valid_until)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,${verifiedBy},${verifyAt},${validUntil}) RETURNING *`, values);
    return result.rows[0];
  }

  async deactivate(client: PoolClient, id: string) {
    return (await client.query('UPDATE emergency_directory SET active=false,updated_at=now() WHERE id=$1', [id])).rowCount;
  }

  async audit(client: PoolClient, actor: string, id: string, action: string) {
    await client.query(`INSERT INTO audit_log(actor_user_id,action,target_type,target_id)
      VALUES($1,$2,'emergency_directory',$3)`, [actor,action,id]);
  }
}
