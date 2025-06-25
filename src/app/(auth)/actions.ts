
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { NextResponse } from 'next/server';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, "Password is required"),
});

export async function login(prevState: any, formData: FormData) {
  const cookieStore = cookies();
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { error: 'Invalid email or password format.' };
  }

  const { email, password } = parsed.data;

  // Since we need to return a response to set cookies, we can't use
  // a shared Supabase client instance. We create one here with the
  // correct cookie handlers for this specific response.
  const response = NextResponse.redirect(new URL('/dashboard', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
        set: (name, value, options) => response.cookies.set(name, value, options),
        remove: (name, options) => response.cookies.set(name, '', { ...options, maxAge: -1 }),
      },
    }
  );

  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  });

  if (error) {
    // If there's an error, we don't redirect. We return the error state to the form.
    // We create a new, non-redirecting response to avoid issues.
    return { error: error.message };
  }

  if (!data.session) {
    // This handles the case where email confirmation is required.
    return { error: 'Login failed: Please check your inbox for a confirmation link.' };
  }
  
  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    // If setup is incomplete, redirect to the setup page.
    const setupResponse = NextResponse.redirect(new URL('/setup-incomplete', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));
    // We need to re-create the client with the new response object to set the cookies.
    const setupSupabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get: (name) => cookieStore.get(name)?.value,
            set: (name, value, options) => setupResponse.cookies.set(name, value, options),
            remove: (name, options) => setupResponse.cookies.set(name, '', { ...options, maxAge: -1 }),
          },
        }
    );
    // We still need to sign in the user again for this response context.
    await setupSupabase.auth.signInWithPassword({ email, password });
    return setupResponse;
  }

  revalidatePath('/', 'layout');
  // On success, return the response object which now has the Set-Cookie headers.
  // The browser will follow the redirect and the new request will have the auth cookie.
  return response;
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
        if (data.user.identities && data.user.identities.length === 0) {
            return { error: "This user already exists. Please try logging in or check your email for a confirmation link." }
        }
        revalidatePath('/', 'layout');
        return { success: true };
    }
    
    return { error: "An unexpected error occurred during sign up." };
}
