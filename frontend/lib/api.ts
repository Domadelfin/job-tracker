export const STATUSES = ['wishlist', 'applied', 'interviewing', 'offer', 'rejected'] as const;
export type Status = (typeof STATUSES)[number];

export const STATUS_LABELS: Record<Status, string> = {
  wishlist: 'Wishlist',
  applied: 'Applied',
  interviewing: 'Interviewing',
  offer: 'Offer',
  rejected: 'Rejected',
};

export interface Application {
  id: number;
  company: string;
  role: string;
  status: Status;
  location: string | null;
  job_url: string | null;
  applied_on: string | null;
  notes: string | null;
  created_at: string;
  updated_at: string;
}

export type ApplicationInput = Partial<Omit<Application, 'id' | 'created_at' | 'updated_at'>>;

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const res = await fetch(`/api${path}`, {
    ...init,
    headers: { 'Content-Type': 'application/json', ...init?.headers },
  });
  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new Error(body?.errors?.join(', ') ?? `Request failed (${res.status})`);
  }
  return (res.status === 204 ? undefined : await res.json()) as T;
}

export const api = {
  list: () => request<Application[]>('/applications'),
  create: (input: ApplicationInput) =>
    request<Application>('/applications', { method: 'POST', body: JSON.stringify(input) }),
  update: (id: number, input: ApplicationInput) =>
    request<Application>(`/applications/${id}`, { method: 'PATCH', body: JSON.stringify(input) }),
  remove: (id: number) => request<void>(`/applications/${id}`, { method: 'DELETE' }),
};
