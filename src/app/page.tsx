
import { redirect } from 'next/navigation';

export default function HomePage() {
  // All redirection logic is handled in `src/middleware.ts`.
  // If a user somehow lands here, the middleware will catch them
  // and redirect to either /login or /dashboard.
  // We can add a fallback redirect here just in case.
  redirect('/login');
}
