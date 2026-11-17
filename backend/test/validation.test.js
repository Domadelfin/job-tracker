import { test } from 'node:test';
import assert from 'node:assert/strict';
import { validateApplication } from '../src/validation.js';

test('accepts a valid application and trims strings', () => {
  const { data, errors } = validateApplication({
    company: '  Acme  ',
    role: 'Cloud Engineer',
    job_url: 'https://acme.com/jobs/1',
    applied_on: '2026-11-14',
  });
  assert.deepEqual(errors, []);
  assert.equal(data.company, 'Acme');
});

test('requires company and role on create', () => {
  const { errors } = validateApplication({});
  assert.deepEqual(errors, ['company is required', 'role is required']);
});

test('partial updates do not require company/role', () => {
  const { data, errors } = validateApplication({ status: 'offer' }, { partial: true });
  assert.deepEqual(errors, []);
  assert.deepEqual(data, { status: 'offer' });
});

test('rejects unknown status', () => {
  const { errors } = validateApplication({ company: 'A', role: 'B', status: 'ghosted' });
  assert.match(errors[0], /status must be one of/);
});

test('rejects non-http URLs (e.g. javascript:)', () => {
  const { errors } = validateApplication({ company: 'A', role: 'B', job_url: 'javascript:alert(1)' });
  assert.deepEqual(errors, ['job_url must be an http(s) URL']);
});

test('rejects malformed dates', () => {
  const { errors } = validateApplication({ company: 'A', role: 'B', applied_on: '14/11/2026' });
  assert.match(errors[0], /YYYY-MM-DD/);
});

test('ignores unknown fields (no column injection)', () => {
  const { data } = validateApplication({ company: 'A', role: 'B', 'role; DROP TABLE x': '1' });
  assert.deepEqual(Object.keys(data).sort(), ['company', 'role']);
});

test('nullable fields accept null, required fields do not', () => {
  assert.deepEqual(validateApplication({ notes: null }, { partial: true }).errors, []);
  assert.deepEqual(validateApplication({ company: null }, { partial: true }).errors, ['company cannot be empty']);
});
