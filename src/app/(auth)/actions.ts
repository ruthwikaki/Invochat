
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

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    // Supabase returns a specific error for unconfirmed emails, but it's better to check for the session.
    if (error.message === 'Email not confirmed') {
      return { error: 'Login failed: Please check your inbox to confirm your email address.' };
    }
    return { error: error.message };
  }
  
  // After a successful login attempt, we MUST check if a session was actually created.
  // If email confirmation is required, Supabase will not return an error, but data.session will be null.
  if (!data.session) {
      return { error: 'Login failed: Please check your email for a confirmation link.' };
  }

  revalidatePath('/', 'layout');
  redirect('/dashboard');
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
        // This is a Supabase-specific check for when a user already exists
        // but has not confirmed their email.
        if (data.user.identities && data.user.identities.length === 0) {
            return { error: "This user already exists. Please try logging in or check your email for a confirmation link." }
        }
        revalidatePath('/', 'layout');
        return { success: true };
    }
    
    return { error: "An unexpected error occurred during sign up." };
}
