'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { NextResponse } from 'next/server';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export async function login(formData: FormData) {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:9003';

  if (!parsed.success) {
    const url = new URL('/login', siteUrl);
    url.searchParams.set('error', 'Invalid email or password format.');
    return NextResponse.redirect(url);
  }

  const { email, password } = parsed.data;

  // We need a response object to attach cookies to
  let response = NextResponse.redirect(new URL('/dashboard', siteUrl));

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

  if (error || !data.session) {
    const url = new URL('/login', siteUrl);
    const msg = error?.message || 'Login failed: Please check your inbox for a confirmation link.';
    url.searchParams.set('error', msg);
    return NextResponse.redirect(url);
  }

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    // Re-create the response object for the new redirect target
    response = NextResponse.redirect(new URL('/setup-incomplete', siteUrl));
    
    // We need to re-create the client bound to the *new* response object
    // to ensure the session cookie is set for the /setup-incomplete page.
    const supabaseSetup = createServerClient(
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
    // Persist the session for the setup-incomplete redirect
    await supabaseSetup.auth.setSession({ access_token: data.session.access_token, refresh_token: data.session.refresh_token });
  }

  revalidatePath('/', 'layout');
  return response;
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(6, "Password must be at least 6 characters."),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(formData: FormData) {
    const parsed = signupSchema.safeParse(Object.fromEntries(formData));
    const siteUrl = process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:9003';

    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        const url = new URL('/signup', siteUrl);
        url.searchParams.set('error', errorMessages);
        return NextResponse.redirect(url);
    }

    const { email, password, companyName } = parsed.data;
    
    // This is a dummy response object that will be replaced by a redirect.
    const response = NextResponse.next();

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
        const url = new URL('/signup', siteUrl);
        url.searchParams.set('error', error.message);
        return NextResponse.redirect(url);
    }

    if (data.user) {
        if (data.user.identities && data.user.identities.length === 0) {
            const url = new URL('/signup', siteUrl);
            url.searchParams.set('error', "This user already exists.");
            return NextResponse.redirect(url);
        }
        revalidatePath('/', 'layout');
        const url = new URL('/signup', siteUrl);
        url.searchParams.set('success', 'true');
        return NextResponse.redirect(url);
    }
    
    const url = new URL('/signup', siteUrl);
    url.searchParams.set('error', "An unexpected error occurred.");
    return NextResponse.redirect(url);
}
