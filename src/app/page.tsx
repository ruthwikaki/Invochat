import { headers } from 'next/headers';

export default async function RootPage() {
  console.log('🔍 Root page accessed');
  
  try {
    const headersList = headers();
    const host = headersList.get('host');
    const userAgent = headersList.get('user-agent');
    
    console.log('📍 Host:', host);
    console.log('🌐 User-Agent:', userAgent);
    
    // Test environment variables
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const hasSupabaseKey = !!process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
    
    console.log('🔑 Supabase URL:', supabaseUrl);
    console.log('🔑 Has Supabase Key:', hasSupabaseKey);
    
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-100">
        <div className="max-w-2xl mx-auto p-8">
          <h1 className="text-4xl font-bold text-green-600 mb-6">
            ✅ Root Page Working!
          </h1>
          <div className="space-y-4 text-lg">
            <p><strong>Host:</strong> {host}</p>
            <p><strong>Supabase URL:</strong> {supabaseUrl || 'Missing'}</p>
            <p><strong>Has Supabase Key:</strong> {hasSupabaseKey ? 'Yes' : 'No'}</p>
            <p><strong>Environment:</strong> {process.env.NODE_ENV}</p>
          </div>
          <div className="mt-8 space-x-4">
            <a href="/login" className="bg-blue-500 text-white px-4 py-2 rounded">
              Go to Login
            </a>
            <a href="/signup" className="bg-green-500 text-white px-4 py-2 rounded">
              Go to Signup
            </a>
          </div>
        </div>
      </div>
    );
  } catch (error) {
    console.error('❌ Error in root page:', error);
    return (
      <div className="min-h-screen flex items-center justify-center bg-red-100">
        <div className="text-center">
          <h1 className="text-4xl font-bold text-red-600 mb-4">Error in Root Page</h1>
          <pre className="text-left bg-red-50 p-4 rounded">
            {error instanceof Error ? error.message : String(error)}
          </pre>
        </div>
      </div>
    );
  }
}
