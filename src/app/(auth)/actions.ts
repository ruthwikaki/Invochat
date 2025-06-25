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
  
  // This is the correct pattern for a server action that needs to set cookies
  // and then redirect. We create the response upfront.
  const response = NextResponse.redirect(new URL('/dashboard', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookies().get(name)?.value,
        // The `set` method has to be passed the `response` object to be able
        // to set the cookie.
        set: (name, value, options) => response.cookies.set(name, value, options),
        remove: (name, options) => response.cookies.set(name, '', { ...options, maxAge: -1 }),
      },
    }
  );

  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    // We can't redirect here because we need to return the error message to the form.
    // So we'll redirect on the client-side for the error case. A bit of a hack, but necessary with useFormState.
    // A better approach would be to not use useFormState and redirect with a query param.
    // But for now, we return the error message.
    const redirectUrl = new URL('/login', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000');
    redirectUrl.searchParams.set('error', error.message);
    return { error: error.message };
  }
  
  if (!data.session) {
    return { error: 'Login failed: Please check your inbox for a confirmation link.' };
  }

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
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
    // We need to sign in again to set the cookie on the new response object
    await supabaseSetup.auth.signInWithPassword({ email, password });
    return setupResponse;
  }

  revalidatePath('/', 'layout');
  // Return the response object which has the auth cookies set
  return response;
}


const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, "Password must be at least 6 characters"),
  companyName: z.string().min(1, "Company name is required"),
});


export async function signup(prevState: any, formData: FormData) {
    const parsed = signupSchema.safeParse(Object.fromEntries(formData));
    
    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        return { error: errorMessages };
    }

    const { email, password, companyName } = parsed.data;

    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get: (name) => cookies().get(name)?.value,
            // A no-op for signup, as we are not setting a session cookie here.
            // The user must confirm their email first.
            set: () => {},
            remove: () => {},
          },
        }
    );


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
