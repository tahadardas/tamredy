import { BadRequestException } from '@nestjs/common';
import { PageArgs, parsePage } from './pagination.js';
export function validatedPage(limit:unknown,cursor:unknown,scope:string):PageArgs {
  try { return parsePage(limit,cursor,scope); }
  catch { throw new BadRequestException({code:'INVALID_PAGINATION',message:'Use limit 1..50 and a valid nextCursor for this list'}); }
}
