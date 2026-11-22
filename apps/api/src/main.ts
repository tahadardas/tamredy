import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module.js';
async function bootstrap() {
  if(!process.env.JWT_SECRET || process.env.JWT_SECRET.length<32) throw new Error('JWT_SECRET must be set to >=32 characters');
  const app=await NestFactory.create(AppModule,{rawBody:true});
  app.use(helmet());
  app.enableCors({origin:(process.env.ALLOWED_ORIGINS??'http://localhost:5173').split(','),credentials:false});
  app.useGlobalPipes(new ValidationPipe({whitelist:true,forbidNonWhitelisted:true,transform:true,transformOptions:{enableImplicitConversion:true}}));
  await app.listen(Number(process.env.API_PORT??3000),'0.0.0.0');
}
void bootstrap();
