import express from 'express';
import { config } from './config.js';
import { pool } from './db.js';
import { migrate } from './migrate.js';
import { applicationsRouter } from './routes/applications.js';

const app = express();
app.disable('x-powered-by');
app.use(express.json({ limit: '100kb' }));

// Everything lives under /api because the ALB will route /api/* to this
// service and everything else to the Next.js frontend.

// Liveness: used by the ALB health check. Deliberately does NOT touch the DB,
// so a brief DB blip doesn't make the ALB kill healthy containers.
app.get('/api/health', (_req, res) => res.json({ status: 'ok' }));

// Readiness: handy for debugging connectivity to RDS from inside the VPC.
app.get('/api/health/db', async (_req, res) => {
  try {
    await pool.query('SELECT 1');
    res.json({ status: 'ok', database: 'reachable' });
  } catch (err) {
    console.error('DB health check failed:', err.message);
    res.status(503).json({ status: 'error', database: 'unreachable' });
  }
});

app.use('/api/applications', applicationsRouter);

app.use('/api', (_req, res) => res.status(404).json({ errors: ['Not found'] }));

// Express 5 forwards rejected promises from async handlers here.
app.use((err, _req, res, _next) => {
  if (err.type === 'entity.parse.failed') {
    return res.status(400).json({ errors: ['Invalid JSON body'] });
  }
  console.error(err);
  res.status(500).json({ errors: ['Internal server error'] }); // never leak internals
});

await migrate();

const server = app.listen(config.port, () => {
  console.log(`API listening on port ${config.port}`);
});

// ECS sends SIGTERM before stopping a task (during deploys and scale-in).
// Finish in-flight requests and close DB connections cleanly.
for (const signal of ['SIGTERM', 'SIGINT']) {
  process.on(signal, () => {
    console.log(`${signal} received, shutting down`);
    server.close(async () => {
      await pool.end();
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10_000).unref();
  });
}
