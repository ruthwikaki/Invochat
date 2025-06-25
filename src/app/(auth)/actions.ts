'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';
import crypto from 'crypto';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export async function login(formData: FormData) {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));

  if (!parsed.success) {
    redirect(`/login?error=${encodeURIComponent('Invalid email or password format.')}`);
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
    const msg = error?.message || 'Login failed: Please check your credentials.';
    redirect(`/login?error=${encodeURIComponent(msg)}`);
  }

  const { access_token, refresh_token } = data.session;

  // Re-set the session explicitly to ensure cookie is stored
  await supabase.auth.setSession({ access_token, refresh_token });

  const companyId = data.user.app_metadata?.company_id;

  // Redirect based on setup completion
  if (!companyId) {
    redirect('/setup-incomplete');
  }

  redirect('/dashboard');
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(6, "Password must be at least 6 characters."),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(formData: FormData) {
    const parsed = signupSchema.safeParse(Object.fromEntries(formData));

    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        redirect(`/signup?error=${encodeURIComponent(errorMessages)}`);
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
            emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/dashboard`,
            data: {
                company_name: companyName,
                company_id: crypto.randomUUID(),
            }
        }
    });

    if (error) {
        redirect(`/signup?error=${encodeURIComponent(error.message)}`);
    }

    if (data.user) {
        // Handle case where user already exists but isn't confirmed
        if (data.user.identities && data.user.identities.length === 0) {
            redirect(`/signup?error=${encodeURIComponent("This user already exists.")}`);
        }
        redirect('/signup?success=true');
    }
    
    redirect(`/signup?error=${encodeURIComponent("An unexpected error occurred during signup.")}`);
}
