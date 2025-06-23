
'use server';

import { adminAuth } from '@/lib/firebase/admin';
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
    // Using the admin client which bypasses RLS.
    // 1. Create the company first to get a company_id.
    const { data: companyData, error: companyError } = await supabaseAdmin
      .from('companies')
      .insert({ name: companyName })
      .select('id')
      .single();

    if (companyError) {
      // This could happen if a company name must be unique, for example.
      return { success: false, error: `Could not create company: ${companyError.message}`};
    }
    const companyId = companyData.id;

    // 2. Create the user in Firebase Auth.
    const userRecord = await adminAuth.createUser({
      email,
      password,
      displayName: email,
    });
    
    // 3. Create the user profile in Supabase, linking it to the Firebase UID and new company.
    // Your schema confirmed the column is 'firebase_uid'.
    const { error: userProfileError } = await supabaseAdmin
      .from('users')
      .insert({ firebase_uid: userRecord.uid, company_id: companyId, email: userRecord.email });

    if (userProfileError) {
        // This is a critical failure. The user exists in Firebase but not in our DB.
        // A robust system would delete the Firebase user here to allow a retry.
        console.error("CRITICAL: Firebase user created but Supabase profile creation failed.", userRecord.uid, userProfileError);
        // Clean up the created company
        await supabaseAdmin.from('companies').delete().eq('id', companyId);
        throw new Error(`Could not create user profile in database: ${userProfileError.message}`);
    }
  
    // 4. Set custom claims on the Firebase user for easy access in server actions.
    await adminAuth.setCustomUserClaims(userRecord.uid, { company_id: companyId });

    return { success: true, error: null };

  } catch (error: any) {
    console.error('Sign-up server action error:', error);
    let errorMessage = 'An unexpected error occurred during sign-up.';
    if (error.code === 'auth/email-already-exists') {
      errorMessage = 'This email address is already in use by another account.';
    } else if (error.message) {
      errorMessage = error.message;
    }
    // Attempt to find and clean up a potentially created company if user creation failed.
    // This is a simple cleanup and might need to be more robust in a production system.
    if (companyName) {
        const {data: company} = await supabaseAdmin.from('companies').select('id').eq('name', companyName).single();
        if(company) {
            await supabaseAdmin.from('companies').delete().eq('id', company.id);
        }
    }
    return { success: false, error: errorMessage };
  }
}
