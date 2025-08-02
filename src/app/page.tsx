import { createServerClient } from '@/lib/supabase/admin';
import { redirect } from 'next/navigation';
import { LandingPage } from '@/components/landing/landing-page';

export default async function RootPage() {
    try {
        const supabase = createServerClient();
        const { data: { session }, error } = await supabase.auth.getSession();

        // If there's an auth error, still show landing page
        if (error) {
            console.warn('Auth error on root page:', error.message);
            return <LandingPage />;
        }

        if (session) {
            return redirect('/dashboard');
        }

        return <LandingPage />;
    } catch (error) {
        console.error('Error in root page:', error);
        // Fallback to landing page if anything fails
        return <LandingPage />;
    }
}
