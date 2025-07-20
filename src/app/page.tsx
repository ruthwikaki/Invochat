
import { redirect } from 'next/navigation';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { LandingPage } from '@/components/landing/landing-page';

export default async function AppRootPage() {
    const cookieStore = cookies();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    
    if (!supabaseUrl || !supabaseAnonKey) {
        // In a real app, you might want to show a more user-friendly error page.
        throw new Error('Supabase environment variables are not set.');
    }

    const supabase = createServerClient(
      supabaseUrl,
      supabaseAnonKey,
      {
        cookies: {
          get(name: string) {
            return cookieStore.get(name)?.value
          },
        },
      }
    );

    const { data: { session } } = await supabase.auth.getSession();

    // If the user is already logged in, redirect them from the landing page
    // to their dashboard.
    if (session) {
        redirect('/dashboard');
    }

    // If there is no session, we should show the landing page.
    return <LandingPage />;
}
