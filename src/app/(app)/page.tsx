
// This file is intentionally blank.
// The root of the authenticated app now redirects to /dashboard via middleware logic.
import { redirect } from 'next/navigation';

export default function AppRootPage() {
    redirect('/dashboard');
}
