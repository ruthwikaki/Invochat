
import { redirect } from 'next/navigation';

export default function HomePage() {
  // All redirection logic is now handled in `src/middleware.ts`.
  // This page should ideally not be reached, but as a fallback,
  // we redirect to the dashboard. The middleware will handle
  // unauthenticated users and redirect them to /login before this page renders.
  redirect('/dashboard');
}
