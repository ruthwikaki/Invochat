
'use server';

import { supabaseAdmin, isSupabaseAdminEnabled, supabaseAdminError } from '@/lib/supabase/admin';

const SignUpSchema = {
  email: (val: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val),
  password: (val: string) => val.length >= 6,
  companyName: (val: string) => val.length >= 2,
};


export async function signUpWithEmailAndPassword(formData: FormData) {
  if (!isSupabaseAdminEnabled || !supabaseAdmin) {
      return { success: false, error: supabaseAdminError || 'Database admin client is not configured.' };
  }
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const companyName = formData.get('companyName') as string;
  let companyId: string | null = null;
  const DEMO_COMPANY_ID = '550e8400-e29b-41d4-a716-446655440001';
  const DEMO_COMPANY_NAME = 'Demo Company';


  // Basic server-side validation
  if (!SignUpSchema.email(email)) {
    return { success: false, error: 'Invalid email format.' };
  }
  if (!SignUpSchema.password(password)) {
    return { success: false, error: 'Password must be at least 6 characters.' };
  }
  if (!SignUpSchema.companyName(companyName)) {
    return { success: false, error: 'Company name is required.' };
  }

  try {
    // 1. Determine company ID
    if (companyName === DEMO_COMPANY_NAME) {
        companyId = DEMO_COMPANY_ID;
        const { data: demoCompany, error: findError } = await supabaseAdmin
            .from('companies')
            .select('id')
            .eq('id', DEMO_COMPANY_ID)
            .single();
        
        if (findError && findError.code !== 'PGRST116') { // PGRST116 = 'single row not found'
             throw new Error(`Could not verify demo company: ${findError.message}`);
        }

        if (!demoCompany) {
            const { error: createDemoError } = await supabaseAdmin
                .from('companies')
                .insert({ id: DEMO_COMPANY_ID, name: DEMO_COMPANY_NAME });
            if (createDemoError) {
                throw new Error(`Could not create demo company: ${createDemoError.message}`);
            }
        }

    } else {
        const { data: companyData, error: companyError } = await supabaseAdmin
        .from('companies')
        .insert({ name: companyName })
        .select('id')
        .single();

        if (companyError) {
          throw new Error(`Could not create company: ${companyError.message}`);
        }
        companyId = companyData.id;
    }


    // 2. Create the user in Supabase Auth, setting company_id in metadata
    const { data: { user }, error: authError } = await supabaseAdmin.auth.admin.createUser({
      email,
      password,
      email_confirm: true, // Auto-confirm user for simplicity
      app_metadata: {
        company_id: companyId,
      }
    });

    if (authError) {
      // Clean up the created company if it wasn't the demo one
      if (companyName !== DEMO_COMPANY_NAME && companyId) {
          await supabaseAdmin.from('companies').delete().eq('id', companyId);
      }
      throw new Error(`Could not create user: ${authError.message}`);
    }

    if (!user) {
        throw new Error('User creation did not return a user object.');
    }
    
    // 3. Create the user profile in Supabase public.users table.
    // Based on RLS policies, the `id` column links to `auth.uid()`.
    const { error: userProfileError } = await supabaseAdmin
      .from('users')
      .insert({ id: user.id, company_id: companyId, email: user.email });

    if (userProfileError) {
        // This is a critical failure. The user exists in Supabase Auth but not in our public DB.
        await supabaseAdmin.auth.admin.deleteUser(user.id);
        // Clean up the created company if it wasn't the demo one
        if (companyName !== DEMO_COMPANY_NAME && companyId) {
            await supabaseAdmin.from('companies').delete().eq('id', companyId);
        }
        throw new Error(`Could not create user profile in database: ${userProfileError.message}`);
    }

    return { success: true, error: null };

  } catch (error: any) {
    console.error('Sign-up server action error:', error);
    let errorMessage = 'An unexpected error occurred during sign-up.';
    if (error.message) {
        errorMessage = error.message;
    }
    if (error.message?.includes('User already exists')) {
        errorMessage = 'This email address is already in use by another account.';
    }
    
    return { success: false, error: errorMessage };
  }
}
