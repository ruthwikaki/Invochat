
'use server';

import { z } from 'zod';
import { createClient } from '@/lib/supabase/server';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, "Password is required"),
});

export async function login(prevState: any, formData: FormData) {
  const cookieStore = cookies();
  const supabase = createClient(cookieStore);

  const parsed = loginSchema.safeParse(Object.fromEntries(formData));

  if (!parsed.success) {
    return { error: 'Invalid email or password format.' };
  }

  const { email, password } = parsed.data;

  const { error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    return { error: error.message };
  }
  
  // Revalidate the entire app to ensure layout reflects the new auth state
  revalidatePath('/', 'layout');
  return redirect('/dashboard');
}


const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, "Password must be at least 6 characters"),
  companyName: z.string().min(1, "Company name is required"),
});


export async function signup(prevState: any, formData: FormData) {
    const cookieStore = cookies();
    const supabase = createClient(cookieStore);

    const parsed = signupSchema.safeParse(Object.fromEntries(formData));
    
    if (!parsed.success) {
        // Concatenate errors for better feedback
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        return { error: errorMessages };
    }

    const { email, password, companyName } = parsed.data;

    const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
            data: {
                company_name: companyName,
            }
        }
    });

    if (error) {
        return { error: error.message };
    }

    if (data.user) {
        // If email confirmation is required, this will be true
        if (data.user.identities && data.user.identities.length === 0) {
            return { error: "An error occurred, but the user was not created. Please try again." }
        }
        revalidatePath('/');
        return { success: true };
    }
    
    return { error: "An unexpected error occurred during sign up." };
}
