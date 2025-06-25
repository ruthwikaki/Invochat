
'use server';

import { z } from 'zod';
import { createServerClient, type CookieOptions } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { revalidatePath } from 'next/cache';
import { NextResponse } from 'next/server';

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

  // Create a response to return
  const response = NextResponse.redirect(new URL('/dashboard', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get: (name) => cookies().get(name)?.value,
        set: (name, value, options) => response.cookies.set(name, value, options),
        remove: (name, options) => response.cookies.set(name, '', { ...options, maxAge: -1 }),
      },
    }
  );

  const { data, error } = await supabase.auth.signInWithPassword({ email, password });

  if (error) return { error: error.message };
  if (!data.session) return { error: 'Login failed: Please check your inbox for a confirmation link.' };

  const companyId = data.user.app_metadata?.company_id;
  if (!companyId) {
    const setupResponse = NextResponse.redirect(new URL('/setup-incomplete', process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));
    // Need to re-create the client bound to the *new* response object
    const supabaseSetup = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
      {
        cookies: {
          get: (name) => cookies().get(name)?.value,
          set: (name, value, options) => setupResponse.cookies.set(name, value, options),
          remove: (name, options) => setupResponse.cookies.set(name, '', { ...options, maxAge: -1 }),
        },
      }
    );
    // Re-authenticate to ensure the cookie is set on the setupResponse
    await supabaseSetup.auth.signInWithPassword({ email, password });
    return setupResponse;
  }

  revalidatePath('/', 'layout');
  return response;
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

// A temporary redirect function until the Next.js types are fixed
// see: https://github.com/vercel/next.js/issues/52179
function redirect(url: string) {
    return NextResponse.redirect(new URL(url, process.env.NEXT_PUBLIC_SITE_URL || 'http://localhost:3000'));
}
