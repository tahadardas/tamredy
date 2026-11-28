import { Redis } from 'ioredis';
import type pg from 'pg';
import { readLiveLocation, validLocation, locationPolicyPayload } from '../../../packages/backend-policy/live-location.mjs';

let redis: Redis | null=null;
function connection():Redis|null {
  if (process.env.LIVE_LOCATION_REDIS_ENABLED!=='true' || !process.env.REDIS_URL) return null;
  redis??=new Redis(process.env.REDIS_URL,{enableOfflineQueue:false,maxRetriesPerRequest:1,commandTimeout:1500});
  return redis;
}
/** A null set selects bounded fresh PostGIS candidates. An empty set means no Redis candidates. */
export async function dispatchLocations(client:pg.PoolClient,requestId:string,radius:number):Promise<Record<string,unknown>[]|null> {
  if (process.env.LIVE_LOCATION_REDIS_ENABLED!=='true') return null;
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
    // Bound concurrency and batch size without truncating the eligible pool.
    for (let offset=0;offset<ids.length;offset+=32) {
      await Promise.all(ids.slice(offset,offset+32).map(async nurseId=>{
        const location=await readLiveLocation({nurseId,redis:cache,db:client,redisEnabled:true,allowPostgresFallback:false});
        if (location && validLocation(location,Number(request.search_max_location_seconds??120),Number(request.search_max_accuracy_meters??100)))
          candidates.push({nurseId,...locationPolicyPayload(location)});
      }));
    }
    return candidates;
  } catch(error) {
    if (process.env.LOCATION_POSTGRES_FALLBACK_ENABLED==='true') return null;
    throw error;
  }
}
export async function closeLocationReader():Promise<void> { await redis?.quit();redis=null; }
