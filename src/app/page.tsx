import { createServerClient } from '@/lib/supabase/admin';
import { redirect } from 'next/navigation';
import { LandingPage } from '@/components/landing/landing-page';

// The root of the app checks auth status and redirects.
// The middleware has already run, so we can trust the session state.
export default async function RootPage() {
    const supabase = createServerClient();

    const { data: { session } } = await supabase.auth.getSession();

    if (session) {
        return redirect('/dashboard');
    }

    return <LandingPage />;
}
