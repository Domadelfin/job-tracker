// Health check endpoint for the frontend's ALB target group.
// (It can't live under /api because the ALB routes /api/* to the backend.)
export const dynamic = 'force-dynamic';

export function GET() {
  return Response.json({ status: 'ok' });
}
