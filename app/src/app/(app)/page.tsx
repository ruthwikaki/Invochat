import { redirect } from 'next/navigation';

// The root of the authenticated app redirects to the dashboard.
// This is hit after the middleware confirms the user is authenticated.
export default function AppRootPage() {
    redirect('/dashboard');
}
