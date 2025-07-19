
'use server';

import { z } from 'zod';
import { cookies, headers } from 'next/headers';
import { redirect } from 'next/navigation';
import { revalidatePath } from 'next/cache';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { rateLimit } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { getErrorMessage, isError } from '@/lib/error-handler';
import { withTimeout } from '@/lib/async-utils';
import { validateCSRF } from '@/lib/csrf';
import { config } from '@/config/app-config';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import crypto from 'crypto';

const AUTH_TIMEOUT = 15000; // 15 seconds

function getSupabaseClient() {
    const cookieStore = cookies();
    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
    const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

    if (!supabaseUrl || !supabaseAnonKey) {
        throw new Error('Supabase URL or anonymous key is not configured.');
    }
    
    return createServerClient(
        supabaseUrl,
        supabaseAnonKey,
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
  password: z.string().min(1, 'Password is required'),
});

export async function login(formData: FormData) {
  try {
    validateCSRF(formData);
    
    const parsed = loginSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
      const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
      throw new Error(errorMessages);
    }
    const { email, password } = parsed.data;

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'auth', config.ratelimit.auth, 60, true);
    if (limited) {
      throw new Error('Too many requests. Please try again in a minute.');
    }
    
    const supabase = getSupabaseClient();
    const { data, error } = await withTimeout(
        supabase.auth.signInWithPassword({ email, password }),
        AUTH_TIMEOUT,
        'Authentication service is not responding. Please try again later.'
    );

    if (error) {
      if (error.message.includes('Email not confirmed')) {
        throw new Error('Please check your inbox to confirm your email address before signing in.');
      }
      if (error.message.includes('Invalid login credentials')) {
        throw new Error('Invalid email or password. Please try again.');
      }
      throw error;
    }
    
    if (!data.session) {
      throw new Error('Login failed. Please check your credentials.');
    }

  } catch (e) {
      if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
        throw e;
      }
      const errorMessage = getErrorMessage(e);
      logger.error('Login action failed:', errorMessage);
      return redirect(`/login?error=${encodeURIComponent(errorMessage)}`);
  }
  
  revalidatePath('/', 'layout');
  redirect('/dashboard');
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(8, "Password must be at least 8 characters."),
  confirmPassword: z.string(),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(formData: FormData) {
  try {
    validateCSRF(formData);

    const parsed = signupSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        throw new Error(errorMessages);
    }
    const { email, password, confirmPassword, companyName } = parsed.data;
    
    // Constant-time comparison for password confirmation
    const passBuf = Buffer.from(password);
    const confirmBuf = Buffer.from(confirmPassword);
    if (passBuf.length !== confirmBuf.length || !crypto.timingSafeEqual(passBuf, confirmBuf)) {
        throw new Error("Passwords do not match.");
    }

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'auth', config.ratelimit.auth, 60, true);
    if (limited) {
      logger.warn(`[Rate Limit] Blocked signup attempt from IP: ${ip}`);
      throw new Error('Too many requests. Please try again in a minute.');
    }
    
    const adminSupabase = getServiceRoleClient();
    
    const { data: { user }, error } = await withTimeout(
      adminSupabase.auth.admin.createUser({
          email,
          password,
          email_confirm: false, // Auto-confirm user for smoother onboarding
          app_metadata: {
              company_name: companyName,
          }
      }),
      AUTH_TIMEOUT,
      'Signup service is not responding. Please try again later.'
    );
    
    if (error) {
        if (error.message.includes('unique constraint') || error.message.includes('User already registered')) {
            throw new Error('A user with this email address already exists.');
        }
        throw new Error(error.message);
    }

    if (!user) {
        throw new Error("An unexpected error occurred during signup.");
    }
    
    // Manually sign in the user after successful creation
    const supabase = getSupabaseClient();
    const { error: signInError } = await supabase.auth.signInWithPassword({ email, password });
    if (signInError) {
        throw new Error(`Account created, but automatic sign-in failed: ${signInError.message}`);
    }
    
  } catch(e) {
      if (isError(e) && e.message.includes('NEXT_REDIRECT')) {
        throw e;
      }
      const errorMessage = getErrorMessage(e);
      logger.error('Signup action failed:', errorMessage);
      return redirect(`/signup?error=${encodeURIComponent(errorMessage)}`);
  }

  revalidatePath('/', 'layout');
  redirect('/dashboard');
}


const requestPasswordResetSchema = z.object({
    email: z.string().email("Please enter a valid email address."),
});

export async function requestPasswordReset(formData: FormData) {
  try {
    validateCSRF(formData);
    const parsed = requestPasswordResetSchema.safeParse(Object.fromEntries(formData));
    if (!parsed.success) {
        throw new Error(parsed.error.issues[0].message);
    }
    
    const { email } = parsed.data;

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'password_reset', 3, 300, true);
    if (limited) {
      throw new Error('Too many password reset requests. Please try again in 5 minutes.');
    }

    const supabase = getSupabaseClient();
    const redirectTo = process.env.NEXT_PUBLIC_SITE_URL;
    if (!redirectTo) {
        throw new Error("Site URL is not configured for password reset email.");
    }

    const { error } = await withTimeout(
      supabase.auth.resetPasswordForEmail(email, {
          redirectTo: `${redirectTo}/update-password`,
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
    password: z.string().min(8, "Password must be at least 8 characters long."),
});

export async function updatePassword(formData: FormData) {
    try {
        validateCSRF(formData);
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
