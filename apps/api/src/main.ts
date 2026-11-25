import 'reflect-metadata';
import { NestFactory } from '@nestjs/core';
import { ValidationPipe } from '@nestjs/common';
import helmet from 'helmet';
import { AppModule } from './app.module.js';
import { HttpTelemetryInterceptor } from './common/http-telemetry.interceptor.js';
async function bootstrap() {
  if(!process.env.JWT_SECRET || process.env.JWT_SECRET.length<32) throw new Error('JWT_SECRET must be set to >=32 characters');
  if(process.env.NODE_ENV==='production' && !process.env.ALLOWED_ORIGINS) throw new Error('ALLOWED_ORIGINS is required in production');
  const app=await NestFactory.create(AppModule,{rawBody:true});
  app.getHttpAdapter().getInstance().disable('x-powered-by');
  const isSslEnforced = process.env.ENFORCE_SSL === 'true';
  app.use(
    helmet({
      contentSecurityPolicy: isSslEnforced ? undefined : false,
      hsts: isSslEnforced ? undefined : false,
      crossOriginResourcePolicy: { policy: 'cross-origin' },
    }),
  );
  const allowedOrigins = process.env.ALLOWED_ORIGINS
    ? process.env.ALLOWED_ORIGINS.split(',').map((s) => s.trim()).filter(Boolean)
    : ['http://localhost:5173'];
  app.enableCors({ origin: allowedOrigins, credentials: false, exposedHeaders:['X-Correlation-ID'] });
  app.useGlobalInterceptors(new HttpTelemetryInterceptor());
  app.useGlobalPipes(new ValidationPipe({whitelist:true,forbidNonWhitelisted:true,transform:true,transformOptions:{enableImplicitConversion:true}}));
  await app.listen(Number(process.env.API_PORT??3000),'0.0.0.0');
}
void bootstrap();
