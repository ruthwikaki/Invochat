
'use server';

import { adminAuth } from '@/lib/firebase/admin';
import { supabaseAdmin } from '@/lib/supabase/admin';

const SignUpSchema = {
  email: (val: string) => /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(val),
  password: (val: string) => val.length >= 6,
  companyName: (val: string) => val.length >= 2,
};


export async function signUpWithEmailAndPassword(formData: FormData) {
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
    // 1. Create company in Supabase
    const { data: companyData, error: companyError } = await supabaseAdmin
      .from('companies')
      .insert({ name: companyName })
      .select('id')
      .single();

    if (companyError) throw new Error(`Could not create company: ${companyError.message}`);
    const companyId = companyData.id;

    // 2. Create user in Firebase Auth
    const userRecord = await adminAuth.createUser({
      email,
      password,
      displayName: email,
    });

    // 3. Create user profile in Supabase
     const { error: userProfileError } = await supabaseAdmin
      .from('users')
      .insert({ id: userRecord.uid, company_id: companyId });

    if (userProfileError) throw new Error(`Could not create user profile: ${userProfileError.message}`);

    // 4. Set custom claims on Firebase user
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
