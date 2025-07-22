
'use server';

import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { redirect } from 'next/navigation';
import { generateCSRFToken, validateCSRF } from '@/lib/csrf';

export async function login(formData: FormData) {
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
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
    // Note: The CSRF token is expected to be passed in the form data by the client component.
    validateCSRF(formData);
    const { error } = await supabase.auth.signInWithPassword({
        email,
        password,
    });
    if (error) {
        logError(error, { context: 'Login failed' });
        redirect(`/login?error=${encodeURIComponent(error.message)}`);
    }
  } catch (e) {
    const message = getErrorMessage(e);
    logError(e, { context: 'Login exception' });
    redirect(`/login?error=${encodeURIComponent(message)}`);
  }
  
  revalidatePath('/', 'layout');
  redirect('/dashboard');
}


export async function signup(formData: FormData) {
  const companyName = formData.get('companyName') as string;
  const email = formData.get('email') as string;
  const password = formData.get('password') as string;
  const confirmPassword = formData.get('confirmPassword') as string;
  
  if (password !== confirmPassword) {
      redirect('/signup?error=Passwords do not match');
  }

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

  try {
    validateCSRF(formData);
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          company_name: companyName,
        },
        emailRedirectTo: `${process.env.NEXT_PUBLIC_SITE_URL}/auth/callback`,
      },
    });

    if (error) {
      logError(error, { context: 'Signup failed' });
      redirect(`/signup?error=${encodeURIComponent(error.message)}`);
    }
  } catch (e) {
      const message = getErrorMessage(e);
      logError(e, { context: 'Signup exception' });
      redirect(`/signup?error=${encodeURIComponent(message)}`);
  }

  revalidatePath('/', 'layout');
  redirect('/login?message=Check your email to continue signing up.');
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
      validateCSRF(formData);
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
        validateCSRF(formData);
        const { error } = await supabase.auth.updateUser({ password });
        if (error) {
            logError(error, { context: 'Password update failed' });
            redirect(`/update-password?error=${encodeURIComponent(error.message)}`);
        }
    } catch (e) {
        const message = getErrorMessage(e);
        logError(e, { context: 'Password update exception' });
        redirect(`/update-password?error=${encodeURIComponent(message)}`);
    }

    redirect('/login?message=Your password has been updated successfully.');
}
