import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Redis } from 'ioredis';

/** Cache aside for PUBLIC, non-security-critical reference data only.
 * Do not cache user permissions, nurse qualifications, GPS, bookings or money.
 * Redis failures degrade to PostgreSQL and never block the API.
 */
@Injectable()
export class ReferenceCacheService implements OnModuleDestroy {
  private readonly redis: Redis | null;
  private readonly inFlight=new Map<string,Promise<unknown>>();
  constructor() {
    this.redis=process.env.REDIS_URL ? new Redis(process.env.REDIS_URL,{
      lazyConnect:true,maxRetriesPerRequest:1,connectTimeout:800,
      retryStrategy:()=>null,
    }) : null;
    this.redis?.on('error',()=>{/* report via monitoring; degrade to DB */});
  }
  private async connection():Promise<Redis|null> {
    if(!this.redis)return null;
    try{
      if(this.redis.status==='wait')await this.redis.connect();
      return this.redis.status==='ready'?this.redis:null;
    }catch{return null;}
  }
  async getOrLoad<T>(namespace:string,load:()=>Promise<T>,ttlSeconds=300):Promise<T> {
    const client=await this.connection();
    if(!client)return load();
    let generation='0';
    try{generation=(await client.get(`tamreedy:ref:gen:${namespace}`))??'0';}catch{return load();}
    const key=`tamreedy:ref:${namespace}:v${generation}`;
    try{const hit=await client.get(key);if(hit!==null)return JSON.parse(hit) as T;}catch{/* fail open to DB */}
    const previous=this.inFlight.get(key);
    if(previous)return previous as Promise<T>;
    const pending=(async()=>{
      const value=await load();
      try{
        // Avoid populating a stale version after an update invalidated the generation.
        const now=await client.get(`tamreedy:ref:gen:${namespace}`);
        if((now??'0')===generation) await client.set(key,JSON.stringify(value),'EX',ttlSeconds);
      }catch{/* do not fail read if Redis failed */}
      return value;
    })();
    this.inFlight.set(key,pending);
    try{return await pending;}finally{this.inFlight.delete(key);}
  }
  async invalidate(namespace:string):Promise<void>{
    const client=await this.connection();
    if(!client)return;
    try{await client.incr(`tamreedy:ref:gen:${namespace}`);}catch{/* the outbox retries invalidation */}
  }
  async onModuleDestroy(){try{await this.redis?.quit();}catch{this.redis?.disconnect();}}
}
