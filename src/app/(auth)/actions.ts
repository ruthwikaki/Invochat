
'use server';

import { z } from 'zod';
import { cookies, headers } from 'next/headers';
import { redirect } from 'next/navigation';
import crypto from 'crypto';
import { revalidatePath } from 'next/cache';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { rateLimit } from '@/lib/redis';
import { logger } from '@/lib/logger';
import { validateCSRFToken, CSRF_COOKIE_NAME, CSRF_FORM_NAME } from '@/lib/csrf';

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

function validateCsrf(formData: FormData, redirectPath: string) {
    const csrfTokenFromForm = formData.get(CSRF_FORM_NAME) as string | null;
    const csrfTokenFromCookie = cookies().get(CSRF_COOKIE_NAME)?.value;

    if (!csrfTokenFromCookie || !csrfTokenFromForm || !validateCSRFToken(csrfTokenFromForm, csrfTokenFromCookie)) {
        logger.warn(`[CSRF] Invalid token for action at path: ${redirectPath}`);
        redirect(`${redirectPath}?error=${encodeURIComponent('Invalid form submission. Please try again.')}`);
    }
}

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1, 'Password is required'),
});

export async function login(formData: FormData) {
  validateCsrf(formData, '/login');

  const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
  const { limited } = await rateLimit(ip, 'auth', 5, 60); // 5 requests per minute per IP
  if (limited) {
    logger.warn(`[Rate Limit] Blocked login attempt from IP: ${ip}`);
    redirect(`/login?error=${encodeURIComponent('Too many requests. Please try again in a minute.')}`);
  }

  const parsed = loginSchema.safeParse(Object.fromEntries(formData));
  if (!parsed.success) {
    redirect(`/login?error=${encodeURIComponent('Invalid email or password format.')}`);
  }

  const { email, password } = parsed.data;
  const supabase = getSupabaseClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error || !data.session) {
    const msg = error?.message || 'Login failed. Check credentials or confirm your email.';
    redirect(`/login?error=${encodeURIComponent(msg)}`);
  }

  const companyId = data.user.app_metadata?.company_id || data.user.user_metadata?.company_id;
  if (!companyId) {
    revalidatePath('/', 'layout');
    revalidatePath('/setup-incomplete', 'page');
    redirect('/setup-incomplete');
  }

  revalidatePath('/', 'layout');
  revalidatePath('/dashboard', 'page');
  redirect('/dashboard');
}


const signupSchema = z.object({
  email: z.string().email("Invalid email format."),
  password: z.string().min(6, "Password must be at least 6 characters."),
  companyName: z.string().min(1, "Company name is required."),
});


export async function signup(formData: FormData) {
    validateCsrf(formData, '/signup');

    const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';
    const { limited } = await rateLimit(ip, 'auth', 5, 60); // 5 requests per minute per IP
    if (limited) {
      logger.warn(`[Rate Limit] Blocked signup attempt from IP: ${ip}`);
      redirect(`/signup?error=${encodeURIComponent('Too many requests. Please try again in a minute.')}`);
    }

    const parsed = signupSchema.safeParse(Object.fromEntries(formData));

    if (!parsed.success) {
        const errorMessages = parsed.error.issues.map(i => i.message).join(', ');
        redirect(`/signup?error=${encodeURIComponent(errorMessages)}`);
    }

    const { email, password, companyName } = parsed.data;
    const supabase = getSupabaseClient();

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
        // If a user object is returned, it means the signup was accepted,
        // either for a new user or to re-send a confirmation to an existing
        // unconfirmed user. In both cases, directing to the success page
        // is the correct action.
        redirect('/signup?success=true');
    }
    
    redirect(`/signup?error=${encodeURIComponent("An unexpected error occurred during signup.")}`);
}


const requestPasswordResetSchema = z.object({
    email: z.string().email("Please enter a valid email address."),
});

export async function requestPasswordReset(formData: FormData) {
    validateCsrf(formData, '/forgot-password');
    const parsed = requestPasswordResetSchema.safeParse(Object.fromEntries(formData));

    if (!parsed.success) {
        redirect(`/forgot-password?error=${encodeURIComponent(parsed.error.issues[0].message)}`);
    }

    const supabase = getSupabaseClient();
    const { error } = await supabase.auth.resetPasswordForEmail(parsed.data.email, {
        redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/update-password`,
    });
    
    if (error) {
        logger.error("Password reset error:", error);
        redirect(`/forgot-password?error=${encodeURIComponent(error.message)}`);
    }
    
    redirect('/forgot-password?success=true');
}

const updatePasswordSchema = z.object({
    password: z.string().min(6, "Password must be at least 6 characters long."),
});

export async function updatePassword(formData: FormData) {
    validateCsrf(formData, '/update-password');
    const parsed = updatePasswordSchema.safeParse(Object.fromEntries(formData));

    if (!parsed.success) {
        redirect(`/update-password?error=${encodeURIComponent(parsed.error.issues[0].message)}`);
    }
    
    const supabase = getSupabaseClient();

    // The user should be in a session from the password recovery link
    const { error } = await supabase.auth.updateUser({ password: parsed.data.password });

    if (error) {
        redirect(`/update-password?error=${encodeURIComponent(error.message)}`);
    }

    redirect('/login?message=Your password has been updated successfully.');
}
