
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

export default async function RootPage() {
    try {
        console.log('🚀 Root page executing...');
        
        const cookieStore = cookies();
        console.log('🍪 Cookies available');
        
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
        
        console.log('📡 Supabase client created');

        const { data: { session }, error } = await supabase.auth.getSession();
        
        if (error) {
            console.error('❌ Session error:', error);
            throw error;
        }
        
        console.log('✅ Session check complete, user exists:', !!session?.user);

        if (session) {
            console.log('➡️ Redirecting to dashboard');
            redirect('/dashboard');
        } else {
            console.log('➡️ Redirecting to login');
            redirect('/login');
        }
    } catch (error) {
        console.error('💥 Root page error:', error);
        // In a real app, you might want a fallback UI here instead of throwing,
        // but for debugging, re-throwing is perfect.
        throw error;
    }
}
