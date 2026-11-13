import { readFileSync } from 'node:fs';
import pg from 'pg';
import { config } from './config.js';

function sslOptions() {
  if (!config.db.ssl) return false;
  if (!config.db.sslCaPath) {
    throw new Error('DB_SSL=true requires DB_SSL_CA_PATH so the server certificate can be verified');
  }
  return {
    rejectUnauthorized: true,
    ca: readFileSync(config.db.sslCaPath, 'utf8'),
  };
}

export const pool = new pg.Pool({
  host: config.db.host,
  port: config.db.port,
  database: config.db.database,
  user: config.db.user,
  password: config.db.password,
  ssl: sslOptions(),
  // db.t4g.micro has a small connection limit; keep each task's pool modest.
  max: 5,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});

pool.on('error', (err) => {
  console.error('Unexpected idle client error', err);
});
