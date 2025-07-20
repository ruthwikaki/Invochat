import { redirect } from 'next/navigation';

// The root of the authenticated app redirects to the dashboard.
export default function AppRootPage() {
    redirect('/dashboard');
}
