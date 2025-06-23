
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
    // If the user wants to join the demo company, assign them to it.
    // Otherwise, create a new company for them.
    if (companyName === DEMO_COMPANY_NAME) {
        companyId = DEMO_COMPANY_ID;
        // Ensure the demo company record exists.
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


    // 2. Create the user in Firebase Auth.
    const userRecord = await adminAuth.createUser({
      email,
      password,
      displayName: email,
    });
    
    // 3. Create the user profile in Supabase, linking it to the Firebase UID and new company.
    const { error: userProfileError } = await supabaseAdmin
      .from('users')
      .insert({ firebase_uid: userRecord.uid, company_id: companyId, email: userRecord.email });

    if (userProfileError) {
        // This is a critical failure. The user exists in Firebase but not in our DB.
        await adminAuth.deleteUser(userRecord.uid);
        // Clean up the created company if it wasn't the demo one
        if (companyName !== DEMO_COMPANY_NAME) {
            await supabaseAdmin.from('companies').delete().eq('id', companyId);
        }
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
    
    return { success: false, error: errorMessage };
  }
}
