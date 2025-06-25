
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { NextResponse } from 'next/server';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, "Password is required"),
});

export async function login(prevState: any, formData: FormData) {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    return { error: 'Invalid email or password format.' };
  }

  const { email, password } = parsed.data;

  // Create a real redirect response that we can write cookies to.
  const response = NextResponse.redirect(new URL('/dashboard', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookies().get(name)?.value,
        set: (name, value, options) => response.cookies.set(name, value, options),
        remove: (name, options) => response.cookies.set(name, '', { ...options, maxAge: -1 }),
      },
    }
  );

  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) return { error: error.message };
  if (!data.session) return { error: 'Login failed: Please check your inbox for a confirmation link.' };

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    // If setup is incomplete, we need a different redirect response.
    // We must create a new response and a new client bound to it to set the cookies correctly.
    const setupResponse = NextResponse.redirect(new URL('/setup-incomplete', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));
    const supabaseSetup = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get: (name) => cookies().get(name)?.value,
          set: (name, value, options) => setupResponse.cookies.set(name, value, options),
          remove: (name, options) => setupResponse.cookies.set(name, '', { ...options, maxAge: -1 }),
        },
      }
    );
    // Re-trigger sign-in to populate cookies on the new response object
    await supabaseSetup.auth.signInWithPassword({ email, password });
    return setupResponse;
  }

  revalidatePath('/', 'layout');
  return response;
}


const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, "Password must be at least 6 characters"),
  companyName: z.string().min(1, "Company name is required"),
});


export async function signup(prevState: any, formData: FormData) {
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        { cookies: { get: (name) => cookies().get(name)?.value } }
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
