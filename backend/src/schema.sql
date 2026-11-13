-- Idempotent schema: safe to run on every startup.

CREATE TABLE IF NOT EXISTS applications (
  id          SERIAL PRIMARY KEY,
  company     TEXT        NOT NULL CHECK (length(company) BETWEEN 1 AND 200),
  role        TEXT        NOT NULL CHECK (length(role) BETWEEN 1 AND 200),
  status      TEXT        NOT NULL DEFAULT 'applied'
              CHECK (status IN ('wishlist', 'applied', 'interviewing', 'offer', 'rejected')),
  location    TEXT,
  job_url     TEXT,
  applied_on  DATE,
  notes       TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS applications_status_idx ON applications (status);
