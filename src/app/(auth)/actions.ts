
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

const FAILED_LOGIN_ATTEMPTS_KEY_PREFIX = 'failed_login_attempts:';
const MAX_LOGIN_ATTEMPTS = 5;
const LOCKOUT_DURATION_SECONDS = 900; // 15 minutes

export async function login(formData: FormData): Promise<{ success: boolean; error?: string; }> {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const cookieStore = cookies();
  const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';

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

    const { limited } = await rateLimit(ip, 'login_attempt', config.ratelimit.auth, 3600);
    if (limited) {
        return { success: false, error: 'Too many login attempts. Please try again in an hour.' };
    }

    const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
    });
    
    if (error) {
        logError(error, { context: 'Login failed' });
        
        if (isRedisEnabled) {
            const failedAttemptsKey = `${FAILED_LOGIN_ATTEMPTS_KEY_PREFIX}${email}`;
            const failedAttempts = await redisClient.incr(failedAttemptsKey);
            await redisClient.expire(failedAttemptsKey, LOCKOUT_DURATION_SECONDS);

            if (failedAttempts >= MAX_LOGIN_ATTEMPTS) {
                const serviceSupabase = getServiceRoleClient();
                const { data: { user } } = await serviceSupabase.auth.admin.getUserByEmail(email);
                if (user) {
                   await serviceSupabase.auth.admin.updateUserById(user.id, {
                       ban_duration: `${LOCKOUT_DURATION_SECONDS}s`
                   });
                }
                logError(new Error(`Account locked for user ${email}`), { context: 'Account Lockout Triggered', ip});
            }
        }
        
        return { success: false, error: 'Invalid login credentials.' };
    }

    if (isRedisEnabled) {
      await redisClient.del(`${FAILED_LOGIN_ATTEMPTS_KEY_PREFIX}${email}`);
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
