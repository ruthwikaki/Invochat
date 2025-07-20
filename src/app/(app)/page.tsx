// This file is intentionally blank. The root of the authenticated app now redirects or is handled by the dashboard.
// This can be removed or used for a different default page in the future.
import { redirect } from 'next/navigation';

export default function AppRootPage() {
    redirect('/dashboard');
}
