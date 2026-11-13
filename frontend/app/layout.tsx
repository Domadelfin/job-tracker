import type { Metadata } from 'next';
import './globals.css';

export const metadata: Metadata = {
  title: 'Job Tracker',
  description: 'Track job applications from wishlist to offer',
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
