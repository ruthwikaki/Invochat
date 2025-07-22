
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

// The root of the app checks auth status and redirects.
// The middleware has already run, so we can trust the session state.
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

    if (session) {
        return redirect('/dashboard');
    }

    return redirect('/login');
}
