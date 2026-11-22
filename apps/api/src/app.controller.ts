import { Controller, Get } from '@nestjs/common';
@Controller() export class AppController {
  @Get('/health') health(){return {service:'tamreedy-api',status:'ok',phase:'foundation-1'};}
}
