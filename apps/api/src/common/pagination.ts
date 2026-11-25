import { createHmac, timingSafeEqual } from 'node:crypto';

export interface CursorPoint { at: string; id: string; rank?: string | null; }
export interface PageArgs { limit: number; cursor: CursorPoint | null; }
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const ISO_TIME = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?Z$/;

function secret(): string {
  const key=process.env.JWT_SECRET;
  if(!key || key.length<32) throw new Error('JWT_SECRET >=32 characters required for cursor signing');
  return key;
}
function sign(body:string):string { return createHmac('sha256',secret()).update(body).digest('base64url'); }
export function encodeCursor(point:CursorPoint,scope:string):string {
  const body=Buffer.from(JSON.stringify({v:1,...point,scope})).toString('base64url');
  return `${body}.${sign(body)}`;
}
export function decodeCursor(value:string,scope:string):CursorPoint {
  if(value.length>1024) throw new Error('INVALID_CURSOR');
  const parts=value.split('.');
  if(parts.length!==2 || !parts[0] || !parts[1]) throw new Error('INVALID_CURSOR');
  const expected=Buffer.from(sign(parts[0]));
  const received=Buffer.from(parts[1]);
  if(expected.length!==received.length || !timingSafeEqual(expected,received)) throw new Error('INVALID_CURSOR');
  try {
    const data=JSON.parse(Buffer.from(parts[0],'base64url').toString('utf8'));
    if(data.v!==1 || data.scope!==scope || typeof data.at!=='string' || !ISO_TIME.test(data.at)
      || !Number.isFinite(Date.parse(data.at)) || typeof data.id!=='string' || !UUID.test(data.id)) throw Error();
    if(data.rank!==undefined && data.rank!==null && (typeof data.rank!=='string' || data.rank.length>64)) throw Error();
    return {at:data.at,id:data.id, ...(data.rank!==undefined ? {rank:data.rank} : {})};
  }catch { throw new Error('INVALID_CURSOR'); }
}
export function parsePage(rawLimit:unknown, rawCursor:unknown, scope:string):PageArgs {
  let limit=20;
  if(rawLimit!==undefined){
    const raw=String(rawLimit);
    if(!/^[1-9]\d{0,2}$/.test(raw)) throw new Error('INVALID_PAGE_LIMIT');
    limit=Number(raw);
  }
  if(limit>50) throw new Error('INVALID_PAGE_LIMIT');
  if(rawCursor!==undefined && (typeof rawCursor!=='string' || !rawCursor)) throw new Error('INVALID_CURSOR');
  return {limit,cursor:rawCursor ? decodeCursor(rawCursor as string,scope) : null};
}
export function makePage<T extends {id:string;created_at: string | Date;cursor_created_at?:string;cursor_id?:string}>(rows:T[],limit:number,scope:string) {
  const hasMore=rows.length>limit;
  const items=rows.slice(0,limit);
  const last=items.at(-1);
  return {items,hasMore,nextCursor:hasMore && last
    ? encodeCursor({id:last.cursor_id ?? last.id,at:last.cursor_created_at ?? new Date(last.created_at).toISOString()},scope)
    : null};
}
