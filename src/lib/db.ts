import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export const supabase = createServerClient(
  process.env.NEXT_PUBLIC_SUPABASE_URL!,
  process.env.SUPABASE_SERVICE_KEY!,
  {
    cookies: {
      get(name: string) {
        return cookies().get(name)?.value;
      },
    },
  }
);
