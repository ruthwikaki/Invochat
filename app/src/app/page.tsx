import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export default async function RootPage() {
    // This page should never be reached because middleware handles redirects
    // But if it does get reached, show a simple landing page
    
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

    return (
        <div className="min-h-screen flex items-center justify-center bg-gray-50">
            <div className="max-w-md w-full space-y-8">
                <div className="text-center">
                    <h1 className="text-3xl font-bold text-gray-900">ARVO</h1>
                    <p className="mt-2 text-gray-600">AI-powered inventory management</p>
                    
                    {session ? (
                        <div className="mt-6">
                            <p className="text-sm text-gray-500">You are logged in</p>
                            <a 
                                href="/dashboard" 
                                className="mt-2 inline-flex items-center px-4 py-2 border border-transparent text-sm font-medium rounded-md text-white bg-primary hover:bg-primary/90"
                            >
                                Go to Dashboard
                            </a>
                        </div>
                    ) : (
                        <div className="mt-6 space-y-3">
                            <a 
                                href="/login" 
                                className="w-full flex justify-center py-2 px-4 border border-transparent rounded-md shadow-sm text-sm font-medium text-white bg-primary hover:bg-primary/90"
                            >
                                Sign In
                            </a>
                            <a 
                                href="/signup" 
                                className="w-full flex justify-center py-2 px-4 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50"
                            >
                                Sign Up
                            </a>
                        </div>
                    )}
                </div>
            </div>
        </div>
    );
}
