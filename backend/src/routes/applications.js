import { Router } from 'express';
import { pool } from '../db.js';
import { STATUSES, validateApplication } from '../validation.js';

export const applicationsRouter = Router();

const COLUMNS = `id, company, role, status, location, job_url,
  to_char(applied_on, 'YYYY-MM-DD') AS applied_on, notes, created_at, updated_at`;

function parseId(raw) {
  const id = Number(raw);
  return Number.isInteger(id) && id > 0 ? id : null;
}

// GET /api/applications?status=interviewing
applicationsRouter.get('/', async (req, res) => {
  const { status } = req.query;
  if (status !== undefined && !STATUSES.includes(status)) {
    return res.status(400).json({ errors: [`status must be one of: ${STATUSES.join(', ')}`] });
  }
  const result = status
    ? await pool.query(`SELECT ${COLUMNS} FROM applications WHERE status = $1 ORDER BY updated_at DESC`, [status])
    : await pool.query(`SELECT ${COLUMNS} FROM applications ORDER BY updated_at DESC`);
  res.json(result.rows);
});

applicationsRouter.get('/:id', async (req, res) => {
  const id = parseId(req.params.id);
  if (!id) return res.status(400).json({ errors: ['Invalid id'] });
  const result = await pool.query(`SELECT ${COLUMNS} FROM applications WHERE id = $1`, [id]);
  if (result.rowCount === 0) return res.status(404).json({ errors: ['Not found'] });
  res.json(result.rows[0]);
});

applicationsRouter.post('/', async (req, res) => {
  const { data, errors } = validateApplication(req.body);
  if (errors.length) return res.status(400).json({ errors });

  const names = Object.keys(data);
  const placeholders = names.map((_, i) => `$${i + 1}`);
  const result = await pool.query(
    `INSERT INTO applications (${names.join(', ')}) VALUES (${placeholders.join(', ')}) RETURNING ${COLUMNS}`,
    Object.values(data),
  );
  res.status(201).json(result.rows[0]);
});

applicationsRouter.patch('/:id', async (req, res) => {
  const id = parseId(req.params.id);
  if (!id) return res.status(400).json({ errors: ['Invalid id'] });

  const { data, errors } = validateApplication(req.body, { partial: true });
  if (errors.length) return res.status(400).json({ errors });
  if (Object.keys(data).length === 0) return res.status(400).json({ errors: ['No fields to update'] });

  // Column names come only from the validator's whitelist, values are parameterised.
  const sets = Object.keys(data).map((name, i) => `${name} = $${i + 1}`);
  const values = [...Object.values(data), id];
  const result = await pool.query(
    `UPDATE applications SET ${sets.join(', ')}, updated_at = now()
     WHERE id = $${values.length} RETURNING ${COLUMNS}`,
    values,
  );
  if (result.rowCount === 0) return res.status(404).json({ errors: ['Not found'] });
  res.json(result.rows[0]);
});

applicationsRouter.delete('/:id', async (req, res) => {
  const id = parseId(req.params.id);
  if (!id) return res.status(400).json({ errors: ['Invalid id'] });
  const result = await pool.query('DELETE FROM applications WHERE id = $1', [id]);
  if (result.rowCount === 0) return res.status(404).json({ errors: ['Not found'] });
  res.status(204).end();
});
