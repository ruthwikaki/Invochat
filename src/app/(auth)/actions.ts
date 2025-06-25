
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { redirect } from 'next/navigation';

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export async function login(prevState: any, formData: FormData) {
  const parsed = loginSchema.safeParse(Object.fromEntries(formData));

  if (!parsed.success) {
    return { error: 'Invalid email or password format.' };
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
    const msg = error?.message || 'Login failed: Please check your inbox for a confirmation link.';
    return { error: msg };
  }

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    return { success: true, redirect: '/setup-incomplete' };
  }

  return { success: true, redirect: '/dashboard' };
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(6, "Password must be at least 6 characters."),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(prevState: any, formData: FormData) {
    const parsed = signupSchema.safeParse(Object.fromEntries(formData));

    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        return { error: errorMessages };
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

    // We must disable email confirmation for this demo to work, otherwise the user
    // will be blocked until they click a link in an email.
    const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
            emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/dashboard`,
            data: {
                company_name: companyName,
            }
        }
    });

    if (error) {
        return { error: error.message };
    }

    if (data.user) {
        // Handle case where user already exists but isn't confirmed
        if (data.user.identities && data.user.identities.length === 0) {
            return { error: "This user already exists." };
        }
        return { success: true, redirect: '/signup?success=true' };
    }
    
    return { error: "An unexpected error occurred." };
}
