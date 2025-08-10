// src/app/api/analytics/dashboard/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
export const runtime = 'nodejs';

function parseRangeToDays(input: string | null) {
  if (!input) return 30;
  const m = /^(\d+)d$/.exec(input.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const days = parseRangeToDays(url.searchParams.get('range'));
  const auth = req.headers.get('authorization');

  if (!auth?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  const ures = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: auth },
  });

  let userObj: any = null;
  try { userObj = await ures.json(); } catch { /* ignore */ }

  if (!ures.ok) {
    console.error('AUTH FAIL', ures.status, userObj);
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Handles both shapes just in case
  const userId = userObj?.id ?? userObj?.user?.id;
  if (!userId) {
    console.error('AUTH OK but no user id', userObj);
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const admin = getServiceRoleClient();
  const { data: cu } = await admin
    .from('company_users')
    .select('company_id')
    .eq('user_id', userId)
    .limit(1)
    .maybeSingle();

  if (!cu?.company_id) {
    return NextResponse.json({ error: 'No company found' }, { status: 403 });
  }

  const { data: metrics, error } = await admin.rpc('get_dashboard_metrics', {
    p_company_id: cu.company_id,
    p_days: days,
  });

  if (error) {
    console.error('RPC error', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }

  return NextResponse.json(metrics ?? {});
}
