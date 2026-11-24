import { Injectable } from '@nestjs/common';
import { missing } from '../common/errors.js';
import type { SavedPlaceDto } from './saved-place.dto.js';
import { SavedPlacesRepository } from './saved-places.repository.js';

@Injectable()
export class SavedPlacesService {
  constructor(private readonly repository: SavedPlacesRepository) {}

  list(user: string) {
    return this.repository.list(user);
  }

  async save(user: string, dto: SavedPlaceDto, id?: string) {
    return (await this.repository.write(user, dto, id)) ?? missing();
  }

  async remove(user: string, id: string) {
    if (!await this.repository.remove(user, id)) missing();
    return { ok: true };
  }

  async use(user: string, id: string) {
    return (await this.repository.markUsed(user, id)) ?? missing();
  }
}
