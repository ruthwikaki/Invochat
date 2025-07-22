
import { redirect } from 'next/navigation';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

async function testSupabaseConnection() {
  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  
  console.log('🔍 Testing Supabase connection...');
  console.log('URL:', supabaseUrl);
  console.log('Anon Key:', supabaseAnonKey ? 'Present' : 'Missing');
  
  if (!supabaseUrl || !supabaseAnonKey) {
    console.error('❌ Supabase credentials missing');
    return { error: 'Supabase credentials not configured' };
  }

  try {
    const cookieStore = cookies();
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

    // Test basic connection
    const { data: { session }, error: sessionError } = await supabase.auth.getSession();
    
    if (sessionError) {
      console.error('❌ Session error:', sessionError);
      return { error: sessionError.message };
    }

    console.log('✅ Supabase connection successful');
    console.log('Session:', session ? 'Active' : 'No session');
    
    return { 
      success: true, 
      hasSession: !!session,
      userId: session?.user?.id,
      userEmail: session?.user?.email 
    };
  } catch (error: any) {
    console.error('❌ Supabase connection failed:', error);
    return { error: error.message };
  }
}

export default async function RootPage() {
    console.log('🚀 Root page accessed');
    
    // Test Supabase connection first
    const connectionTest = await testSupabaseConnection();
    
    if (connectionTest.error) {
        console.error('❌ Connection test failed:', connectionTest.error);
        // Still try to proceed with auth flow
    } else {
        console.log('✅ Connection test passed:', connectionTest);
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

    try {
        const { data: { session }, error } = await supabase.auth.getSession();
        
        if (error) {
            console.error('❌ Auth session error:', error);
            redirect('/login?error=' + encodeURIComponent('Authentication error: ' + error.message));
        }

        console.log('🔐 Session check:', session ? 'User logged in' : 'No session');

        if (session) {
            const companyId = session.user.app_metadata?.company_id || session.user.user_metadata?.company_id;
            console.log('🏢 Company ID:', companyId ? 'Present' : 'Missing');
            
            if (companyId) {
                console.log('➡️ Redirecting to dashboard');
                redirect('/dashboard');
            } else {
                console.log('➡️ Redirecting to setup');
                redirect('/env-check');
            }
        } else {
            console.log('➡️ Redirecting to login');
            redirect('/login');
        }
    } catch (error: any) {
        console.error('❌ Root page error:', error);
        redirect('/login?error=' + encodeURIComponent('System error occurred'));
    }
}
