
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies, headers } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { redirect } from 'next/navigation';
import { isRedisEnabled, rateLimit, redisClient } from '@/lib/redis';
import { config } from '@/config/app-config';
import { getServiceRoleClient } from '@/lib/supabase/admin';

const FAILED_LOGIN_ATTEMPTS_KEY_PREFIX = 'failed_login_attempts:';
const MAX_LOGIN_ATTEMPTS = 5;
const LOCKOUT_DURATION_SECONDS = 900; // 15 minutes

export async function login(formData: FormData) {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const cookieStore = cookies();
  const ip = headers().get('x-forwarded-for') ?? '127.0.0.1';

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

  try {
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

  } catch (e) {
    const message = getErrorMessage(e);
    logError(e, { context: 'Login exception' });
    return { success: false, error: message };
  }
  
  revalidatePath('/', 'layout');
  return { success: true };
}


export async function signup(formData: FormData) {
  const companyName = formData.get('companyName') as string;
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const confirmPassword = formData.get('confirmPassword') as string;
  
  if (password !== confirmPassword) {
      redirect('/signup?error=Passwords do not match');
      return;
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

  try {
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
      redirect(`/signup?error=${encodeURIComponent(error.message)}`);
      return;
    }

    if (!data.user) {
      redirect(`/signup?error=${encodeURIComponent('Could not create user. Please try again.')}`);
      return;
    }

    if (data.user && !data.user.email_confirmed_at && data.user.confirmation_sent_at) {
      redirect('/login?message=Check your email to confirm your account and continue.');
    } else if (data.user && data.user.email_confirmed_at) {
      revalidatePath('/', 'layout');
      redirect('/dashboard?success=Account created successfully');
    } else {
      revalidatePath('/', 'layout');
      redirect('/dashboard?success=Account created successfully');
    }

  } catch (e) {
    const message = getErrorMessage(e);
    logError(e, { context: 'Signup exception' });
    redirect(`/signup?error=${encodeURIComponent(message)}`);
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
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get(name: string) { return cookieStore.get(name)?.value },
        },
      }
    );
    try {
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

    try {
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

export async function setupCompanyForExistingUser(formData: FormData) {
    const companyName = formData.get('companyName') as string;
    if (!companyName) {
        redirect('/env-check?error=Company name is required.');
        return;
    }
    
    const cookieStore = cookies();
    const authSupabase = createServerClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL!,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
        {
          cookies: { get: (name: string) => cookieStore.get(name)?.value },
        }
    );
    
    const { data: { user } } = await authSupabase.auth.getUser();

    if (!user) {
        redirect('/login?error=You must be logged in to perform this action.');
        return;
    }

    const serviceSupabase = getServiceRoleClient();
    
    // 1. Create the company
    const { data: company, error: companyError } = await serviceSupabase
        .from('companies')
        .insert({ name: companyName, owner_id: user.id })
        .select()
        .single();

    if (companyError) {
        logError(companyError, { context: 'Failed to create company for existing user' });
        redirect(`/env-check?error=${encodeURIComponent('Could not create your company.')}`);
        return;
    }

    // 2. Link user to company
    const { error: companyUserError } = await serviceSupabase
        .from('company_users')
        .insert({ company_id: company.id, user_id: user.id, role: 'Owner' });

    if (companyUserError) {
        logError(companyUserError, { context: 'Failed to link existing user to new company' });
        redirect(`/env-check?error=${encodeURIComponent('Could not link user to company.')}`);
        return;
    }

    // 3. Update the user's app_metadata with the new company ID
    const { error: updateUserError } = await serviceSupabase.auth.admin.updateUserById(
        user.id,
        { app_metadata: { ...user.app_metadata, company_id: company.id } }
    );
    
    if (updateUserError) {
        logError(updateUserError, { context: "Failed to update user's app_metadata with company ID" });
        redirect(`/env-check?error=${encodeURIComponent('Could not finalize user setup.')}`);
        return;
    }

    // Revalidate and redirect
    revalidatePath('/', 'layout');
    redirect('/dashboard');
}
