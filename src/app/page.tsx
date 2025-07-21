

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { LandingPage } from '@/components/landing/landing-page';
import { redirect } from 'next/navigation';

// The root of the authenticated app redirects to the dashboard.
// This is hit after the middleware confirms the user is authenticated.
export default async function RootPage() {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
        cookies: {
            get(name: string) {
            return cookieStore.get(name)?.value;
            },
        },
        }
    );
    const { data: { user } } = await supabase.auth.getUser();

    if (user) {
        redirect('/dashboard');
    }

    return (
        <LandingPage />
    );
}
