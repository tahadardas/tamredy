import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';
import { PGlite } from '@electric-sql/pglite';
import { SavedPlacesController } from '../dist/saved-places/saved-places.controller.js';
import { SavedPlacesRepository } from '../dist/saved-places/saved-places.repository.js';
import { SavedPlacesService } from '../dist/saved-places/saved-places.service.js';

test('saved places isolate owners and maintain one default with recent usage', async () => {
  const db = new PGlite();
  try {
    await db.exec('CREATE TABLE users (id uuid PRIMARY KEY DEFAULT gen_random_uuid())');
    await db.exec(await readFile(new URL('../../../infra/db/migrations/026_user_saved_places.sql', import.meta.url), 'utf8'));
    const repo = new SavedPlacesRepository({
      query: (sql, params) => db.query(sql, params),
      transaction: (work) => db.transaction(work),
    });
    const controller = new SavedPlacesController(new SavedPlacesService(repo));
    const makeUser = async (role = 'PATIENT') => ({
      user: { id: (await db.query('INSERT INTO users DEFAULT VALUES RETURNING id')).rows[0].id, role },
    });
    const owner = await makeUser();
    const other = await makeUser();
    const nurse = await makeUser('NURSE');
    const input = {
      label: 'منزل الأسرة', placeType: 'HOME', latitude: 33.5, longitude: 36.3,
      accuracy: 20, formattedAddress: 'دمشق، المزة', isDefault: true,
    };
    const home = await controller.create(owner, input);
    const work = await controller.create(owner, { ...input, label: 'العمل', placeType: 'WORK' });
    assert.deepEqual((await controller.list(owner)).map(row => [row.id, row.is_default]), [
      [work.id, true], [home.id, false],
    ]);
    assert.deepEqual(await controller.list(other), []);
    assert.throws(() => controller.list(nurse), { status: 403 });
    await assert.rejects(controller.update(other, home.id, input), { status: 404 });
    await assert.rejects(controller.use(other, home.id), { status: 404 });
    await assert.rejects(controller.remove(other, home.id), { status: 404 });
    assert.ok((await controller.use(owner, home.id)).last_used_at);
    await controller.update(owner, home.id, input);
    assert.equal((await controller.list(owner))[0].label, input.label);
    await controller.remove(owner, home.id);
    assert.equal((await controller.list(owner)).length, 1);
  } finally {
    await db.close();
  }
});
