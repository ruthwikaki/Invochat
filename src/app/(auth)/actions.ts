
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

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
    redirect(url.toString());
  }

  const { email, password } = parsed.data;

  const cookieStore = cookies();

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookieStore.get(name)?.value,
        set: (name, value, options) => cookieStore.set({ name, value, ...options }),
        remove: (name, options) => cookieStore.set({ name, value: '', ...options }),
      },
    }
  );

  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error || !data.session) {
    const url = new URL('/login', siteUrl);
    const msg = error?.message || 'Login failed: Please check your inbox for a confirmation link.';
    url.searchParams.set('error', msg);
    redirect(url.toString());
  }

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    // The middleware will handle redirecting to /setup-incomplete on the next request
    // after the session cookie has been set.
    redirect('/dashboard');
  }

  // Success, redirect to dashboard.
  // The middleware will handle revalidating the path.
  redirect('/dashboard');
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
        redirect(url.toString());
    }

    const { email, password, companyName } = parsed.data;
    
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get: (name) => cookieStore.get(name)?.value,
            set: (name, value, options) => cookieStore.set({ name, value, ...options }),
            remove: (name, options) => cookieStore.set({ name, value: '', ...options }),
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
        redirect(url.toString());
    }

    if (data.user) {
        if (data.user.identities && data.user.identities.length === 0) {
            const url = new URL('/signup', siteUrl);
            url.searchParams.set('error', "This user already exists.");
            redirect(url.toString());
        }
        const url = new URL('/signup', siteUrl);
        url.searchParams.set('success', 'true');
        redirect(url.toString());
    }
    
    const url = new URL('/signup', siteUrl);
    url.searchParams.set('error', "An unexpected error occurred.");
    redirect(url.toString());
}
