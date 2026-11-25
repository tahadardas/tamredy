import { Injectable, OnModuleDestroy } from '@nestjs/common';
import { Pool, PoolClient, QueryResult, QueryResultRow } from 'pg';

@Injectable()
export class DbService implements OnModuleDestroy {
  private readonly pool: Pool;
  constructor() {
    if (!process.env.DATABASE_URL) throw new Error('DATABASE_URL is required');
    this.pool = new Pool({ connectionString: process.env.DATABASE_URL,max:20,statement_timeout:10000,connectionTimeoutMillis:3000 });
    this.pool.on('error', error=>{
      const code='code' in error && typeof error.code==='string' && /^[A-Z0-9_]{1,40}$/.test(error.code)
        ? error.code : 'DATABASE_CONNECTION_FAILED';
      console.error(JSON.stringify({service:'tamreedy-api',event:'database.pool_error',code}));
    });
  }
  query<T extends QueryResultRow = any>(sql: string, params: unknown[] = []): Promise<QueryResult<T>> {
    return this.pool.query<T>(sql, params);
  }
  async transaction<T>(run: (client: PoolClient) => Promise<T>): Promise<T> {
    const client = await this.pool.connect();
    try {
      await client.query('BEGIN');
      const result = await run(client);
      await client.query('COMMIT');
      return result;
    } catch (e) {
      await client.query('ROLLBACK');
      throw e;
    } finally { client.release(); }
  }
  async onModuleDestroy(): Promise<void> { await this.pool.end(); }
}
