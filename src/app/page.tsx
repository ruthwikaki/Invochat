
import { redirect } from 'next/navigation';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import DashboardPage from './(app)/dashboard/page';

export default async function RootPage() {
    const cookieStore = cookies();
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get(name: string) {
            return cookieStore.get(name)?.value
          },
        },
      }
    );

    const { data: { session } } = await supabase.auth.getSession();

    if (!session) {
        // The middleware should handle this, but as a fallback.
        return redirect('/login');
    }

    // If the user is authenticated, render the dashboard content directly.
    return <DashboardPage />;
}
