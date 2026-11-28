import { Redis } from 'ioredis';
import type pg from 'pg';
import { decodeRedisLocation, validLocation, locationPolicyPayload } from '../../../packages/backend-policy/live-location.mjs';
import { featureCapabilities } from '../../../packages/backend-policy/capabilities.mjs';

const uuid = /^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;

let redis: Redis | null=null;
function connection():Redis|null {
  if (!featureCapabilities().liveLocationRedisEnabled || !process.env.REDIS_URL) return null;
  redis??=new Redis(process.env.REDIS_URL,{enableOfflineQueue:false,maxRetriesPerRequest:1,commandTimeout:1500});
  return redis;
}
/** A null set selects bounded fresh PostGIS candidates. An empty set means no Redis candidates. */
export async function dispatchLocations(client:pg.PoolClient,requestId:string,radius:number):Promise<Record<string,unknown>[]|null> {
  if (!featureCapabilities().liveLocationRedisEnabled) return null;
  try {
    const cache=connection();
    if (!cache) throw new Error('LIVE_LOCATION_REDIS_NOT_CONFIGURED');
    const result=await client.query(`SELECT ST_Y(location::geometry) AS latitude,
      ST_X(location::geometry) AS longitude,search_max_location_seconds,search_max_accuracy_meters
      FROM care_requests WHERE id=$1`,[requestId]);
    const request=result.rows[0];
    if (!request) return [];
    const ids=await cache.call('GEOSEARCH','live:geo:nurses','FROMLONLAT',request.longitude,request.latitude,
      'BYRADIUS',radius,'m','ASC') as string[];
    const candidates:Record<string,unknown>[]=[];
    const validIds = ids.filter(id => uuid.test(id));
    const now = Date.now();
    // Batch round trips without truncating the candidate pool.
    for (let offset=0;offset<validIds.length;offset+=128) {
      const batch = validIds.slice(offset, offset + 128);
      const pipeline = cache.pipeline();
      for (const id of batch) pipeline.hgetall(`live:location:${id}`);
      const replies = await pipeline.exec();
      if (!replies || replies.length !== batch.length) throw new Error('LIVE_LOCATION_REDIS_INCOMPLETE');
      for (let index = 0; index < replies.length; index++) {
        const [error, hash] = replies[index]!;
        if (error) throw error;
        const location = hash && typeof hash === 'object' ? decodeRedisLocation(hash as Record<string, string>) : null;
        if (location?.sessionId && uuid.test(location.sessionId) &&
            validLocation(location, Number(request.search_max_location_seconds ?? 120),
              Number(request.search_max_accuracy_meters ?? 100), now)) {
          // The SQL eligibility function rechecks session ownership/revocation and range.
          candidates.push({nurseId:batch[index]!, ...locationPolicyPayload(location)});
        }
      }
    }
    return candidates;
  } catch(error) {
    if (featureCapabilities().locationPostgresFallbackEnabled) return null;
    throw error;
  }
}
export async function closeLocationReader():Promise<void> { await redis?.quit();redis=null; }
