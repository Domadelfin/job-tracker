import { readFileSync } from 'node:fs';
import { pool } from './db.js';

const schema = readFileSync(new URL('./schema.sql', import.meta.url), 'utf8');

// Arbitrary constant used as a Postgres advisory-lock key. If two ECS tasks
// start at the same moment, only one runs the schema at a time.
const MIGRATION_LOCK_KEY = 727001;

export async function migrate() {
  const client = await pool.connect();
  try {
    await client.query('SELECT pg_advisory_lock($1)', [MIGRATION_LOCK_KEY]);
    await client.query(schema);
    console.log('Database schema is up to date');
  } finally {
    await client.query('SELECT pg_advisory_unlock($1)', [MIGRATION_LOCK_KEY]).catch(() => {});
    client.release();
  }
}
