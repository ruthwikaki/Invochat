import { NextResponse } from 'next/server';
import { supabaseAdmin } from '@/lib/supabase/admin';
import { cookies } from 'next/headers';
import { createServerClient } from '@supabase/ssr';

export async function GET() {
  try {
    // Test 1: Check if we can get the user
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
    
    const { data: { user }, error: userError } = await supabase.auth.getUser();
    const companyId = user?.app_metadata?.company_id;
    
    // Test 2: Check if admin client exists
    const adminExists = !!supabaseAdmin;
    
    // Test 3: Try to execute a simple query
    let queryTest = null;
    let queryError = null;
    
    if (supabaseAdmin && companyId) {
      const { data, error } = await supabaseAdmin.rpc('execute_dynamic_query', {
        query_text: `SELECT SUM(quantity * cost) as total_value FROM inventory WHERE company_id = '${companyId}'`
      });
      queryTest = data;
      queryError = error;
    }
    
    // Test 4: Check Google API key
    const hasGoogleKey = !!process.env.GOOGLE_API_KEY;
    
    return NextResponse.json({
      success: true,
      tests: {
        user: user ? { email: user.email, hasCompanyId: !!companyId, companyId } : null,
        userError,
        adminClientExists: adminExists,
        hasServiceRoleKey: !!process.env.SUPABASE_SERVICE_ROLE_KEY,
        hasGoogleApiKey: hasGoogleKey,
        queryTest,
        queryError: queryError ? { message: queryError.message, details: queryError } : null
      }
    });
    
  } catch (error: any) {
    return NextResponse.json({ 
      success: false,
      error: error.message,
      stack: error.stack 
    });
  }
}
