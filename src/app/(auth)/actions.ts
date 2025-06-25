
'use server';

import { z } from 'zod';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { redirect } from 'next/navigation';
import type { CookieOptions } from '@supabase/ssr';

const loginSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(1, "Password is required."),
});

export async function login(formData: FormData) {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
        set(name: string, value: string, options: CookieOptions) {
          cookieStore.set({ name, value, ...options })
        },
        remove(name: string, options: CookieOptions) {
          cookieStore.set({ name, value: '', ...options })
        },
      },
    }
  );

  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    const errorMessages = parsed.error.issues.map(i => i.message).join(' ');
    return redirect(`/login?error=${encodeURIComponent(errorMessages)}`);
  }

  const { email, password } = parsed.data;
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) {
    return redirect(`/login?error=${encodeURIComponent(error.message)}`);
  }
  
  // The middleware will handle the redirect to /setup-incomplete if needed
  // after the session is established.

  revalidatePath('/', 'layout');
  return redirect('/dashboard');
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
        return redirect(`/signup?error=${encodeURIComponent(errorMessages)}`);
    }

    const { email, password, companyName } = parsed.data;
    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get(name: string) {
                return cookieStore.get(name)?.value
            },
            set(name: string, value: string, options: CookieOptions) {
                cookieStore.set({ name, value, ...options })
            },
            remove(name: string, options: CookieOptions) {
                cookieStore.set({ name, value: '', ...options })
            },
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
        return redirect(`/signup?error=${encodeURIComponent(error.message)}`);
    }

    if (data.user) {
        if (data.user.identities && data.user.identities.length === 0) {
            return redirect(`/signup?error=${encodeURIComponent("This user already exists.")}`);
        }
        revalidatePath('/', 'layout');
        // Redirect to a success page that tells the user to check their email.
        return redirect(`/signup?success=true`);
    }
    
    return redirect(`/signup?error=${encodeURIComponent("An unexpected error occurred.")}`);
}
