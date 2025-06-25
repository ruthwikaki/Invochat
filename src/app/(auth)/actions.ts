
'use server';

import { z } from 'zod';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';

// Reusable Supabase client for Server Actions
function createActionClient() {
    const cookieStore = cookies();
    return createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
            cookies: {
                get(name: string) {
                  return cookieStore.get(name)?.value;
                },
                set(name: string, value: string, options: CookieOptions) {
                  cookieStore.set({ name, value, ...options });
                },
                remove(name: string, options: CookieOptions) {
                  cookieStore.set({ name, value: '', ...options });
                },
            },
        }
    );
}


const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, "Password is required"),
});

export async function login(prevState: any, formData: FormData) {
  const supabase = createActionClient();
  
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
    return { error: error.message };
  }

  if (!data.session) {
    return { error: 'Login failed: Please check your inbox for a confirmation link.' };
  }
  
  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    // Return a specific state for client-side redirect
    return { setupIncomplete: true };
  }

  revalidatePath('/', 'layout');
  // Return success state for client-side redirect
  return { success: true };
}


const signupSchema = z.object({
  email: z.string().email(),
  password: z.string().min(6, "Password must be at least 6 characters"),
  companyName: z.string().min(1, "Company name is required"),
});


export async function signup(prevState: any, formData: FormData) {
    const supabase = createActionClient();

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
