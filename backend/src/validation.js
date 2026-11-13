export const STATUSES = ['wishlist', 'applied', 'interviewing', 'offer', 'rejected'];

const FIELDS = {
  company: { type: 'string', max: 200 },
  role: { type: 'string', max: 200 },
  status: { type: 'status' },
  location: { type: 'string', max: 200, nullable: true },
  job_url: { type: 'url', nullable: true },
  applied_on: { type: 'date', nullable: true },
  notes: { type: 'string', max: 5000, nullable: true },
};

/**
 * Validates a request body. Returns { data, errors }.
 * `partial` = true for PATCH (only validate fields that were sent).
 */
export function validateApplication(body, { partial = false } = {}) {
  const errors = [];
  const data = {};

  if (typeof body !== 'object' || body === null) {
    return { data, errors: ['Body must be a JSON object'] };
  }

  if (!partial) {
    for (const name of ['company', 'role']) {
      if (body[name] === undefined) errors.push(`${name} is required`);
    }
  }

  for (const [name, rule] of Object.entries(FIELDS)) {
    if (!(name in body)) continue;
    let value = body[name];

    if (value === null || value === '') {
      if (rule.nullable) {
        data[name] = null;
        continue;
      }
      errors.push(`${name} cannot be empty`);
      continue;
    }

    if (typeof value !== 'string') {
      errors.push(`${name} must be a string`);
      continue;
    }
    value = value.trim();

    switch (rule.type) {
      case 'string':
        if (value.length === 0 || value.length > rule.max) {
          errors.push(`${name} must be 1-${rule.max} characters`);
          continue;
        }
        break;
      case 'status':
        if (!STATUSES.includes(value)) {
          errors.push(`status must be one of: ${STATUSES.join(', ')}`);
          continue;
        }
        break;
      case 'url':
        try {
          const url = new URL(value);
          if (!['http:', 'https:'].includes(url.protocol)) throw new Error();
        } catch {
          errors.push('job_url must be an http(s) URL');
          continue;
        }
        break;
      case 'date':
        if (!/^\d{4}-\d{2}-\d{2}$/.test(value) || Number.isNaN(Date.parse(value))) {
          errors.push(`${name} must be a date in YYYY-MM-DD format`);
          continue;
        }
        break;
    }
    data[name] = value;
  }

  return { data, errors };
}
