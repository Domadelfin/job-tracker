'use client';

import { FormEvent, useEffect, useMemo, useState } from 'react';
import { api, Application, STATUSES, STATUS_LABELS, Status } from '@/lib/api';

type Filter = Status | 'all';

const EMPTY_FORM = { company: '', role: '', status: 'applied' as Status, location: '', job_url: '', applied_on: '', notes: '' };

export default function HomePage() {
  const [apps, setApps] = useState<Application[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [filter, setFilter] = useState<Filter>('all');
  const [form, setForm] = useState(EMPTY_FORM);
  const [saving, setSaving] = useState(false);

  useEffect(() => {
    api
      .list()
      .then(setApps)
      .catch((e: Error) => setError(e.message))
      .finally(() => setLoading(false));
  }, []);

  const counts = useMemo(() => {
    const c = Object.fromEntries(STATUSES.map((s) => [s, 0])) as Record<Status, number>;
    apps.forEach((a) => c[a.status]++);
    return c;
  }, [apps]);

  const visible = filter === 'all' ? apps : apps.filter((a) => a.status === filter);

  async function handleCreate(e: FormEvent) {
    e.preventDefault();
    setSaving(true);
    setError(null);
    try {
      // Send empty optional fields as null so the API stores NULL, not ''.
      const payload = Object.fromEntries(
        Object.entries(form).map(([k, v]) => [k, v === '' ? null : v]),
      );
      const created = await api.create(payload);
      setApps((prev) => [created, ...prev]);
      setForm(EMPTY_FORM);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setSaving(false);
    }
  }

  async function handleStatus(app: Application, status: Status) {
    setError(null);
    try {
      const updated = await api.update(app.id, { status });
      setApps((prev) => [updated, ...prev.filter((a) => a.id !== app.id)]);
    } catch (err) {
      setError((err as Error).message);
    }
  }

  async function handleDelete(app: Application) {
    if (!confirm(`Delete ${app.role} at ${app.company}?`)) return;
    setError(null);
    try {
      await api.remove(app.id);
      setApps((prev) => prev.filter((a) => a.id !== app.id));
    } catch (err) {
      setError((err as Error).message);
    }
  }

  const set = (field: keyof typeof EMPTY_FORM) => (e: { target: { value: string } }) =>
    setForm((f) => ({ ...f, [field]: e.target.value }));

  return (
    <main className="container">
      <header className="header">
        <h1>Job Tracker</h1>
        <p className="muted">{apps.length} applications</p>
      </header>

      <nav className="pipeline" aria-label="Filter by status">
        <button className={filter === 'all' ? 'chip active' : 'chip'} onClick={() => setFilter('all')}>
          All <span>{apps.length}</span>
        </button>
        {STATUSES.map((s) => (
          <button key={s} className={`chip ${filter === s ? 'active' : ''}`} onClick={() => setFilter(s)}>
            {STATUS_LABELS[s]} <span>{counts[s]}</span>
          </button>
        ))}
      </nav>

      <section className="card">
        <h2>Add application</h2>
        <form className="form" onSubmit={handleCreate}>
          <input required placeholder="Company *" value={form.company} onChange={set('company')} maxLength={200} />
          <input required placeholder="Role *" value={form.role} onChange={set('role')} maxLength={200} />
          <select value={form.status} onChange={set('status')}>
            {STATUSES.map((s) => (
              <option key={s} value={s}>{STATUS_LABELS[s]}</option>
            ))}
          </select>
          <input placeholder="Location" value={form.location} onChange={set('location')} maxLength={200} />
          <input type="url" placeholder="Job posting URL" value={form.job_url} onChange={set('job_url')} />
          <input type="date" aria-label="Applied on" value={form.applied_on} onChange={set('applied_on')} />
          <textarea placeholder="Notes" value={form.notes} onChange={set('notes')} maxLength={5000} rows={2} />
          <button type="submit" className="primary" disabled={saving}>
            {saving ? 'Saving…' : 'Add'}
          </button>
        </form>
      </section>

      {error && <p className="error" role="alert">{error}</p>}

      <section className="list">
        {loading && <p className="muted">Loading…</p>}
        {!loading && visible.length === 0 && <p className="muted">Nothing here yet.</p>}
        {visible.map((app) => (
          <article key={app.id} className="card item">
            <div className="item-main">
              <h3>
                {app.job_url ? (
                  <a href={app.job_url} target="_blank" rel="noopener noreferrer">{app.role}</a>
                ) : (
                  app.role
                )}
              </h3>
              <p className="muted">
                {app.company}
                {app.location && ` · ${app.location}`}
                {app.applied_on && ` · applied ${app.applied_on}`}
              </p>
              {app.notes && <p className="notes">{app.notes}</p>}
            </div>
            <div className="item-actions">
              <select
                aria-label="Status"
                className={`status status-${app.status}`}
                value={app.status}
                onChange={(e) => handleStatus(app, e.target.value as Status)}
              >
                {STATUSES.map((s) => (
                  <option key={s} value={s}>{STATUS_LABELS[s]}</option>
                ))}
              </select>
              <button className="ghost" onClick={() => handleDelete(app)} aria-label={`Delete ${app.role}`}>
                Delete
              </button>
            </div>
          </article>
        ))}
      </section>
    </main>
  );
}
