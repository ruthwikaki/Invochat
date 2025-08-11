// src/lib/api-auth.ts
import { NextRequest } from 'next/server';
import { createServerClient } from '@supabase/ssr';

export class ApiError extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

function getBearer(req: NextRequest) {
  const h = req.headers.get('authorization') || '';
  const m = /^Bearer\s+(.+)$/i.exec(h);
  return m?.[1];
}

export function makeSupabaseForReq(req: NextRequest) {
  // Note: we don’t need cookies setter for simple GET APIs
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      global: {
        headers: {
          // Pass through bearer header so .auth.getUser(token) works
          Authorization: req.headers.get('authorization') || '',
        },
      },
      cookies: {
        get: (name: string) => req.cookies.get(name)?.value,
        set: () => {},
        remove: () => {},
      },
    }
  );
}

export async function requireUser(req: NextRequest) {
  const supabase = makeSupabaseForReq(req);
  const bearer = getBearer(req);

  const { data, error } = bearer
    ? await supabase.auth.getUser(bearer)
    : await supabase.auth.getUser();

  if (error || !data?.user) throw new ApiError(401, 'Unauthorized');
  return { supabase, user: data.user };
}

export function requireCompanyId(user: any) {
  const companyId = user?.app_metadata?.company_id;
  if (!companyId) throw new ApiError(400, 'Missing company_id');
  return companyId as string;
}
