
'use server';

import { z } from 'zod';
import { cookies, headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { rateLimit } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { validateCSRFToken, CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';
import { getErrorMessage, isError } from '@/lib/error-handler';
import { withTimeout } from '@/lib/async-utils';

const AUTH_TIMEOUT = 15000; // 15 seconds

function getSupabaseClient() {
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

function validateCsrf(formData: FormData) {
    const csrfTokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;
    const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;

    if (!csrfTokenFromCookie || !csrfTokenFromForm || !validateCSRFToken(csrfTokenFromForm, csrfTokenFromCookie)) {
        throw new Error('Invalid form submission. Please refresh the page and try again.');
    }
}

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export async function login(formData: FormData) {
  try {
    validateCsrf(formData);
    
    const parsed = loginSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
      const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
      throw new Error(errorMessages);
    }
    const { email, password } = parsed.data;

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'auth', 5, 60);
    if (limited) {
      throw new Error('Too many requests. Please try again in a minute.');
    }
    
    const supabase = getSupabaseClient();
    const { data, error } = await withTimeout(
        supabase.auth.signInWithPassword({ email, password }),
        AUTH_TIMEOUT,
        'Authentication service is not responding. Please try again later.'
    );

    if (error || !data.session) {
      throw new Error(error?.message || 'Login failed. Check credentials or confirm your email.');
    }

    const companyId = data.user.app_metadata?.company_id;
    if (!companyId) {
      revalidatePath('/setup-incomplete', 'page');
      redirect('/setup-incomplete');
    }

  } catch (e) {
      // Allow Next.js's redirect exceptions to propagate
      if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
        throw e;
      }
      const errorMessage = getErrorMessage(e);
      logger.error('Login action failed:', errorMessage);
      return redirect(`/login?error=${encodeURIComponent(errorMessage)}`);
  }
  
  revalidatePath('/dashboard', 'page');
  redirect('/dashboard');
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(6, "Password must be at least 6 characters."),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(formData: FormData) {
  try {
    validateCsrf(formData);

    const parsed = signupSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        throw new Error(errorMessages);
    }
    const { email, password, companyName } = parsed.data;

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'auth', 5, 60);
    if (limited) {
      logger.warn(`[Rate Limit] Blocked signup attempt from IP: ${ip}`);
      throw new Error('Too many requests. Please try again in a minute.');
    }

    const supabase = getSupabaseClient();
    
    const { data, error } = await withTimeout(
      supabase.auth.signUp({
          email,
          password,
          options: {
              emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/dashboard`,
              data: {
                  company_name: companyName,
              }
          }
      }),
      AUTH_TIMEOUT,
      'Signup service is not responding. Please try again later.'
    );
    
    if (error) {
        throw new Error(error.message);
    }

    if (!data.user) {
        throw new Error("An unexpected error occurred during signup.");
    }
    
  } catch(e) {
      if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
        throw e;
      }
      const errorMessage = getErrorMessage(e);
      logger.error('Signup action failed:', errorMessage);
      return redirect(`/signup?error=${encodeURIComponent(errorMessage)}`);
  }

  return redirect('/signup?success=true');
}


const requestPasswordResetSchema = z.object({
    email: z.string().email("Please enter a valid email address."),
});

export async function requestPasswordReset(formData: FormData) {
  try {
    validateCsrf(formData);
    const parsed = requestPasswordResetSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
        throw new Error(parsed.error.issues[0].message);
    }

    const supabase = getSupabaseClient();
    const { error } = await withTimeout(
      supabase.auth.resetPasswordForEmail(parsed.data.email, {
          redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/update-password`,
      }),
      AUTH_TIMEOUT,
      'Password reset service is not responding. Please try again later.'
    );
      
    if (error) {
        logger.error("Password reset error:", error);
        throw new Error(error.message);
    }
    
  } catch (e) {
      if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
        throw e;
      }
      const errorMessage = getErrorMessage(e);
      logger.error('Password reset request failed:', errorMessage);
      return redirect(`/forgot-password?error=${encodeURIComponent(errorMessage)}`);
  }

  return redirect('/forgot-password?success=true');
}

const updatePasswordSchema = z.object({
    password: z.string().min(6, "Password must be at least 6 characters long."),
});

export async function updatePassword(formData: FormData) {
    try {
        validateCsrf(formData);
        const parsed = updatePasswordSchema.safeParse(Object.fromEntries(formData));
        if (!parsed.success) {
            throw new Error(parsed.error.issues[0].message);
        }

        const supabase = getSupabaseClient();
        const { error } = await supabase.auth.updateUser({ password: parsed.data.password });

        if (error) {
            throw new Error(error.message);
        }
    } catch(e) {
        if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
            throw e;
        }
        const errorMessage = getErrorMessage(e);
        logger.error('Update password action failed:', errorMessage);
        return redirect(`/update-password?error=${encodeURIComponent(errorMessage)}`);
    }
    
    return redirect('/login?message=Your password has been updated successfully.');
}

export async function signOut() {
    try {
        const supabase = getSupabaseClient();
        await supabase.auth.signOut();
    } catch (e) {
        logger.error('Sign out failed:', e);
    } finally {
        revalidatePath('/', 'layout');
        redirect('/login');
    }
}
