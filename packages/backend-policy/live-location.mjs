/** Shared Redis/PostGIS reader used by the API and dispatch worker. */
export function decodeRedisLocation(value) {
  if (!value.capturedAtEpochMs || !value.receivedAtEpochMs || !value.sessionId) return null;
  const location = {
    latitude:Number(value.latitude),longitude:Number(value.longitude),
    accuracyMeters:Number(value.accuracyMeters),capturedAt:new Date(Number(value.capturedAtEpochMs)),
    recordedAt:new Date(Number(value.receivedAtEpochMs)),sequenceNumber:Number(value.sequenceNumber),
    sessionId:value.sessionId,source:'redis',
  };
  return validLocation(location,Infinity,Infinity) ? location : null;
}
export function validLocation(value,maxAgeSeconds=120,maxAccuracyMeters=100,now=Date.now()) {
  return Number.isFinite(value.latitude) && Math.abs(value.latitude)<=90
    && Number.isFinite(value.longitude) && Math.abs(value.longitude)<=180
    && Number.isFinite(value.accuracyMeters) && value.accuracyMeters>=0
    && value.accuracyMeters<=maxAccuracyMeters
    && Number.isFinite(value.capturedAt.getTime()) && Number.isFinite(value.recordedAt.getTime())
    && now-value.capturedAt.getTime()<=maxAgeSeconds*1000
    && now-value.recordedAt.getTime()<=maxAgeSeconds*1000
    && value.capturedAt.getTime()<=now+30000;
}
export async function readLiveLocation({nurseId,redis,db,redisEnabled,allowPostgresFallback}) {
  if (redisEnabled) {
    try {
      if (!redis) throw new Error('LIVE_LOCATION_REDIS_NOT_CONFIGURED');
      return decodeRedisLocation(await redis.hgetall(`live:location:${nurseId}`));
    } catch (error) {
      if (!allowPostgresFallback) throw error;
    }
  }
  const result=await db.query(`SELECT ST_Y(location::geometry) AS latitude,
    ST_X(location::geometry) AS longitude,accuracy_m,recorded_at,received_at,captured_at,sequence_number,session_id
    FROM nurse_locations WHERE nurse_id=$1`,[nurseId]);
  const row=result.rows[0];
  if (!row || row.latitude==null || row.longitude==null) return null;
  return {latitude:Number(row.latitude),longitude:Number(row.longitude),
    accuracyMeters:Number(row.accuracy_m??9999),recordedAt:new Date(row.received_at??row.recorded_at),
    capturedAt:new Date(row.captured_at??row.recorded_at),
    sequenceNumber:row.sequence_number==null?null:Number(row.sequence_number),sessionId:row.session_id??null,source:'postgres'};
}
export function locationPolicyPayload(location) {
  return location ? {latitude:location.latitude,longitude:location.longitude,
    accuracyMeters:location.accuracyMeters,capturedAt:location.capturedAt.toISOString(),
    receivedAt:location.recordedAt.toISOString(),sessionId:location.sessionId} : {unavailable:true};
}
