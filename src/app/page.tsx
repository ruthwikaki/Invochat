
import { redirect } from 'next/navigation';

export default function HomePage() {
  // All redirection logic is now handled in `src/middleware.ts`.
  // If a user somehow lands here, we'll redirect them to the dashboard,
  // and the middleware will catch unauthenticated users and send them to login.
  redirect('/dashboard');
}
