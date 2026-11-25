import { Controller, Get, ServiceUnavailableException } from '@nestjs/common';
import { DbService } from './db/db.service.js';

@Controller()
export class AppController {
  constructor(private readonly db: DbService) {}

  @Get('/health')
  health() { return {service:'tamreedy-api',status:'ok'}; }

  @Get('/ready')
  async ready() {
    try {
      await this.db.query('SELECT 1');
    } catch {
      throw new ServiceUnavailableException({code:'DATABASE_UNAVAILABLE'});
    }
    return {service:'tamreedy-api',status:'ready'};
  }
}
