import { BadRequestException, ConflictException, ForbiddenException, GoneException, NotFoundException } from '@nestjs/common';
export function invalid(message: string): never { throw new BadRequestException({ code: 'INVALID_REQUEST', message }); }
export function conflict(code: string): never { throw new ConflictException({ code }); }
export function forbidden(): never { throw new ForbiddenException({code:'FORBIDDEN'}); }
export function gone(): never { throw new GoneException({code:'OFFER_EXPIRED'}); }
export function missing(): never { throw new NotFoundException({code:'NOT_FOUND'}); }
