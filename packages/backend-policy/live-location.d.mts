export interface SharedLocation {
 latitude:number; longitude:number; accuracyMeters:number; capturedAt:Date; recordedAt:Date;
 sequenceNumber:number|null; sessionId:string|null; source:'redis'|'postgres';
}
export interface LocationRedis { hgetall(key:string):Promise<Record<string,string>> }
export interface LocationDb {query(sql:string,params?:unknown[]):Promise<{rows:any[]}>}
export function decodeRedisLocation(value:Record<string,string>):SharedLocation|null;
export function validLocation(value:SharedLocation,maxAgeSeconds?:number,maxAccuracyMeters?:number,now?:number):boolean;
export function readLiveLocation(input:{nurseId:string;redis:LocationRedis|null;db:LocationDb;redisEnabled:boolean;allowPostgresFallback:boolean}):Promise<SharedLocation|null>;
export function locationPolicyPayload(location:SharedLocation|null):Record<string,unknown>;
