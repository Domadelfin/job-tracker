import type { NextConfig } from 'next';

// The browser always calls relative URLs like /api/applications.
//  - On AWS, the ALB sends /api/* straight to the backend service, so these
//    requests never reach Next.js.
//  - Locally there is no ALB, so this rewrite plays its role and forwards /api/*
//    to the backend container. API_URL is read at build time.
const apiUrl = process.env.API_URL ?? 'http://localhost:4000';

const nextConfig: NextConfig = {
  // Produces a minimal self-contained server in .next/standalone -> small Docker image.
  output: 'standalone',
  poweredByHeader: false,
  async rewrites() {
    return [{ source: '/api/:path*', destination: `${apiUrl}/api/:path*` }];
  },
};

export default nextConfig;
