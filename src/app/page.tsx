
import { redirect } from 'next/navigation';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { envValidation } from '@/config/app-config';
import { LandingPage } from '@/components/landing/landing-page';

export default async function RootPage() {
    // If env vars are missing, the layout will render an error page.
    // If Supabase URL is missing, we can't proceed, so we might as well do nothing here.
    if (!envValidation.success) {
      return null;
    }

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
        redirect('/dashboard');
    }

    return <LandingPage />;
}
