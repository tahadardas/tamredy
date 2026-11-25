import {randomUUID} from 'node:crypto';
import {CallHandler, ExecutionContext, Injectable, type NestInterceptor} from '@nestjs/common';

interface RequestMetadata {
  method: string;
  baseUrl?: string;
  route?: {path?: unknown};
  headers: Record<string,string|string[]|undefined>;
}
interface ResponseMetadata {
  statusCode: number;
  setHeader(name: string,value: string): void;
  once(event: 'finish', callback: () => void): void;
}

@Injectable()
export class HttpTelemetryInterceptor implements NestInterceptor {
  intercept(context: ExecutionContext, next: CallHandler) {
    if (context.getType()!=='http') return next.handle();
    const http=context.switchToHttp();
    const request=http.getRequest<RequestMetadata>();
    const response=http.getResponse<ResponseMetadata>();
    const supplied=request.headers['x-correlation-id'];
    const correlationId=typeof supplied==='string' && /^[a-f0-9-]{36}$/i.test(supplied)
      ? supplied : randomUUID();
    const started=performance.now();
    response.setHeader('X-Correlation-ID',correlationId);
    response.once('finish',()=>{
      const route=typeof request.route?.path==='string' ? request.route.path : 'unmatched';
      console.info(JSON.stringify({
        service:'tamreedy-api',event:'http.completed',correlationId,method:request.method,
        route,status:response.statusCode,durationMs:Math.round(performance.now()-started),
      }));
    });
    return next.handle();
  }
}
