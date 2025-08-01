
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { redirect } from 'next/navigation';
import { isRedisEnabled, rateLimit, redisClient } from '@/lib/redis';
import { config } from '@/config/app-config';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { validateCSRF } from '@/lib/csrf';
import { getAuthContext } from '@/lib/auth-helpers';

const FAILED_LOGIN_ATTEMPTS_KEY_PREFIX = 'failed_login_attempts:';
const MAX_LOGIN_ATTEMPTS = 5;
const LOCKOUT_DURATION_SECONDS = 900; // 15 minutes

export async function login(formData: FormData): Promise<{ success: boolean; error?: string; }> {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const cookieStore = cookies();
  const ip = headers().get('x-forwarded-for') ?? headers().get('x-real-ip') ?? '127.0.0.1';

  try {
    await validateCSRF(formData);

    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get(name: string) {
              return cookieStore.get(name)?.value
            },
            set(name: string, value: string, options) {
              try {
                cookieStore.set({ name, value, ...options });
              } catch (error) {
                // The `set` method was called from a Server Component.
              }
            },
            remove(name: string, options) {
              try {
                cookieStore.set({ name, value: '', ...options });
              } catch (error) {
                // The `delete` method was called from a Server Component.
              }
            },
          },
        }
    );

    // Rate limiting by IP for general login attempts
    const { limited } = await rateLimit(ip, 'login_attempt', config.ratelimit.auth, 3600, true);
    if (limited) {
        return { success: false, error: 'Too many login attempts from this location. Please try again in an hour.' };
    }

    // --- Corrected Account Lockout Logic ---
    const serviceSupabase = getServiceRoleClient();
    const { data: { user: existingUser } } = await serviceSupabase.auth.admin.getUserByEmail(email);
    
    // Determine the correct identifier for lockout tracking
    const lockoutIdentifier = existingUser ? `user:${existingUser.id}` : `ip:${ip}`;
    const failedAttemptsKey = `${FAILED_LOGIN_ATTEMPTS_KEY_PREFIX}${lockoutIdentifier}`;

    if (isRedisEnabled) {
      const isLocked = await redisClient.get(`${failedAttemptsKey}:locked`);
      if (isLocked) {
        const ttl = await redisClient.ttl(`${failedAttemptsKey}:locked`);
        return { 
          success: false, 
          error: `Account temporarily locked. Please try again in ${Math.ceil(ttl / 60)} minutes.`
        };
      }
    }

    // Attempt login
    const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
        email,
        password,
    });
    
    if (authError) {
        if (isRedisEnabled) {
            const failedAttempts = await redisClient.incr(failedAttemptsKey);
            await redisClient.expire(failedAttemptsKey, LOCKOUT_DURATION_SECONDS);

            if (failedAttempts >= MAX_LOGIN_ATTEMPTS) {
                await redisClient.setex(`${failedAttemptsKey}:locked`, LOCKOUT_DURATION_SECONDS, 'true');
                
                if (existingUser) {
                    try {
                        await serviceSupabase.auth.admin.updateUserById(existingUser.id, {
                           banned_until: new Date(Date.now() + LOCKOUT_DURATION_SECONDS * 1000).toISOString(),
                        });
                        logError(new Error(`Account locked for user ${existingUser.id}`), { context: 'Account Lockout Triggered' });
                    } catch (banError) {
                        logError(banError, { context: 'Failed to set Supabase ban', userId: existingUser.id });
                    }
                }
                return { 
                    success: false, 
                    error: 'Account temporarily locked due to multiple failed attempts. Please try again in 15 minutes.' 
                };
            }
        }
        return { success: false, error: 'Invalid login credentials.' };
    }

    // Successful login - clear any lockout counters for the user
    if (isRedisEnabled && existingUser) {
      await redisClient.del(`${FAILED_LOGIN_ATTEMPTS_KEY_PREFIX}user:${existingUser.id}`, `${FAILED_LOGIN_ATTEMPTS_KEY_PREFIX}user:${existingUser.id}:locked`);
    }

    revalidatePath('/', 'layout');
    return { success: true };

  } catch (e) {
    const message = getErrorMessage(e);
    logError(e, { context: 'Login exception' });
    return { success: false, error: message };
  }
}


export async function signup(formData: FormData): Promise<{ success: boolean; error?: string; message?: string }> {
  const companyName = formData.get('companyName') as string;
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const confirmPassword = formData.get('confirmPassword') as string;
  
  try {
    await validateCSRF(formData);
    
    if (password !== confirmPassword) {
        return { success: false, error: 'Passwords do not match' };
    }

    const cookieStore = cookies();
    const supabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: {
            get(name: string) {
              return cookieStore.get(name)?.value
            },
            set(name: string, value: string, options) {
              cookieStore.set({ name, value, ...options });
            },
            remove(name: string, options) {
              cookieStore.set({ name, value: '', ...options });
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
        },
      },
    });

    if (error) {
      logError(error, { context: 'Supabase signUp failed' });
      return { success: false, error: error.message };
    }

    if (!data.user) {
      return { success: false, error: 'Could not create user. Please try again.' };
    }

    if (data.user && !data.user.email_confirmed_at && data.user.confirmation_sent_at) {
      return { success: true, message: 'Check your email to confirm your account and continue.' };
    }
    
    revalidatePath('/', 'layout');
    return { success: true };

  } catch (e) {
    const message = getErrorMessage(e);
    logError(e, { context: 'Signup exception' });
    return { success: false, error: message };
  }
}


export async function signOut() {
  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value;
        },
        set(name: string, value: string, options) {
          cookieStore.set({ name, value, ...options });
        },
        remove(name: string, options) {
          cookieStore.set({ name, value: '', ...options });
        },
      },
    }
  );

  await supabase.auth.signOut();
  revalidatePath('/', 'layout');
  redirect('/login');
}


export async function requestPasswordReset(formData: FormData) {
    const email = formData.get('email') as string;
    const cookieStore = cookies();
    try {
        await validateCSRF(formData);
        const supabase = createServerClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL!,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
          {
            cookies: {
              get(name: string) { return cookieStore.get(name)?.value },
            },
          }
        );
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/update-password`,
      });
      if (error) {
        logError(error, { context: 'Password reset request failed' });
        redirect(`/forgot-password?error=${encodeURIComponent(error.message)}`);
      }
    } catch(e) {
      const message = getErrorMessage(e);
      logError(e, { context: 'Password reset exception' });
      redirect(`/forgot-password?error=${encodeURIComponent(message)}`);
    }
    redirect('/forgot-password?success=true');
}


export async function updatePassword(formData: FormData) {
    const password = formData.get('password') as string;
    const confirmPassword = formData.get('confirmPassword') as string;
    const cookieStore = cookies();
   
    try {
        await validateCSRF(formData);

        const supabase = createServerClient(
          process.env.NEXT_PUBLIC_SUPABASE_URL!,
          process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
          {
            cookies: {
              get(name: string) { return cookieStore.get(name)?.value },
              set(name: string, value: string, options) { cookieStore.set({ name, value, ...options }) },
              remove(name: string, options) { cookieStore.set({ name, value: '', ...options }) },
            },
          }
        );

        if (password !== confirmPassword) {
            redirect('/update-password?error=Passwords do not match');
        }

        const { error } = await supabase.auth.updateUser({ password });
        if (error) {
            logError(error, { context: 'Password update failed' });
            redirect(`/update-password?error=${encodeURIComponent(error.message)}`);
        } else {
            await supabase.auth.signOut();
        }
    } catch (e) {
        const message = getErrorMessage(e);
        logError(e, { context: 'Password update exception' });
        redirect(`/update-password?error=${encodeURIComponent(message)}`);
    }

    redirect('/login?message=Your password has been updated successfully. Please sign in again.');
}
