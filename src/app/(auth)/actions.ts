
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, "Password is required"),
});

export async function login(prevState: any, formData: FormData) {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
        set: (name, value, options) => cookieStore.set(name, value, options),
        remove: (name, options) => cookieStore.delete(name, options),
      }
    }
  );

  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { error: 'Invalid email or password format.' };
  }

  const { email, password } = parsed.data;

  // This is the call to Supabase to sign in.
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  // If Supabase returns an explicit error (e.g., "Invalid login credentials"),
  // we show it to the user.
  if (error) {
    return { error: error.message };
  }
  
  // After a login attempt, we MUST check if a session was actually created.
  // If email confirmation is required, Supabase will NOT return an error, but data.session will be null.
  // This is the most common reason for login "failures".
  if (!data.session) {
      return { error: 'Login failed: Please check your inbox for a confirmation link.' };
  }

  // At this point, the user is authenticated and has a session.
  // The Supabase SSR client has automatically set the auth cookie via the cookieStore.
  
  // One final check: Does the user have a company_id?
  // If not, their account setup is incomplete. Redirect them to the setup page.
  // This prevents them from getting stuck if the `handle_new_user` trigger failed.
  // We use a standard redirect here because this is a server-side check after a successful login.
  if (!data.user.app_metadata?.company_id) {
    redirect('/setup-incomplete');
  }

  // If everything is correct, revalidate the cache and signal success to the client.
  revalidatePath('/', 'layout');
  return { success: true };
}


const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, "Password must be at least 6 characters"),
  companyName: z.string().min(1, "Company name is required"),
});


export async function signup(prevState: any, formData: FormData) {
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get: (name) => cookieStore.get(name)?.value,
            set: (name, value, options) => cookieStore.set(name, value, options),
            remove: (name, options) => cookieStore.delete(name, options),
          }
        }
    );


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
