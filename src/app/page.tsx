
import { redirect } from 'next/navigation';

// This is the new root page. Its only job is to redirect users
// to the main dashboard, which is the intended entry point for the app.
// The middleware will handle redirecting unauthenticated users to the login page.
export default function RootPage() {
  redirect('/dashboard');
}
