import { Pool } from "pg";

const connectionString =
  process.env.DATABASE_URL ??
  `postgres://${process.env.POSTGRES_USER ?? "appuser"}:${process.env.POSTGRES_PASSWORD ?? "apppassword"}@${
    process.env.POSTGRES_HOST ?? "localhost"
  }:${process.env.POSTGRES_PORT ?? "5432"}/${process.env.POSTGRES_DB ?? "appdb"}`;

declare global {
  // eslint-disable-next-line no-var
  var __dbPool: Pool | undefined;
}

const pool = global.__dbPool ?? new Pool({ connectionString });
if (!global.__dbPool) {
  global.__dbPool = pool;
}

export const query = (text: string, params?: any[]) => pool.query(text, params);
