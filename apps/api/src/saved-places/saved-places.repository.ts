import { Injectable } from '@nestjs/common';
import type { PoolClient } from 'pg';
import { DbService } from '../db/db.service.js';
import type { SavedPlaceDto } from './saved-place.dto.js';

@Injectable()
export class SavedPlacesRepository {
  constructor(private readonly db: DbService) {}

  async list(user: string) {
    return (await this.db.query(`SELECT * FROM user_saved_places WHERE user_id=$1
      ORDER BY is_default DESC,last_used_at DESC NULLS LAST,created_at DESC,id`, [user])).rows;
  }

  async write(user: string, place: SavedPlaceDto, id?: string) {
    return this.db.transaction(async client => {
      await client.query('SELECT id FROM users WHERE id=$1 FOR UPDATE', [user]);
      if (id && !(await client.query('SELECT id FROM user_saved_places WHERE user_id=$1 AND id=$2 FOR UPDATE', [user, id])).rowCount) return null;
      if (place.isDefault) {
        await client.query('UPDATE user_saved_places SET is_default=false,updated_at=now() WHERE user_id=$1 AND is_default', [user]);
      }
      return this.persist(client, user, place, id);
    });
  }

  private async persist(client: PoolClient, user: string, place: SavedPlaceDto, id?: string) {
    const values = [user, place.label, place.placeType, place.latitude, place.longitude,
      place.accuracy, place.formattedAddress, place.floor ?? null, place.building ?? null,
      place.landmark ?? null, place.notes ?? null, place.isDefault];
    const result = id
      ? await client.query(`UPDATE user_saved_places SET label=$2,place_type=$3,latitude=$4,longitude=$5,
        accuracy=$6,formatted_address=$7,floor=$8,building=$9,landmark=$10,notes=$11,is_default=$12,
        updated_at=now() WHERE user_id=$1 AND id=$13 RETURNING *`, [...values, id])
      : await client.query(`INSERT INTO user_saved_places(user_id,label,place_type,latitude,longitude,
        accuracy,formatted_address,floor,building,landmark,notes,is_default)
        VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING *`, values);
    return result.rows[0];
  }

  async remove(user: string, id: string) {
    return (await this.db.query('DELETE FROM user_saved_places WHERE user_id=$1 AND id=$2', [user, id])).rowCount;
  }

  async markUsed(user: string, id: string) {
    return (await this.db.query('UPDATE user_saved_places SET last_used_at=now() WHERE user_id=$1 AND id=$2 RETURNING *', [user, id])).rows[0];
  }
}
