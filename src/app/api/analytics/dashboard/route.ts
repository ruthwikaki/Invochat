import { NextRequest, NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
export const runtime = 'nodejs';

function parseRangeToDays(input: string | null) {
  if (!input) return 30;
  const m = /^(\d+)\s*d$/.exec(input.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  const url = new URL(req.url);
  const days = parseRangeToDays(url.searchParams.get('range'));

  const auth = req.headers.get('authorization');
  console.log('AUTH HEADER SEEN?', !!auth);
  if (!auth?.startsWith('Bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  console.log('SUPABASE_URL in route:', SUPABASE_URL);
  const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

  // Validate the incoming token with Supabase auth
  const ures = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: ANON_KEY, Authorization: auth },
  });

  if (!ures.ok) {
    // optional: console.log('AUTH FAIL', ures.status, await ures.text());
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const { user } = await ures.json(); // { user: { id, ... } }
  if (!user?.id) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  // Map user -> company
  const admin = getServiceRoleClient();
  const { data: cu, error: cuErr } = await admin
    .from('company_users')
    .select('company_id')
    .eq('user_id', user.id)
    .limit(1)
    .maybeSingle();

  if (cuErr || !cu?.company_id) {
    return NextResponse.json({ error: 'No company found for user' }, { status: 403 });
  }

  // Call your SQL function via RPC
  const { data: metrics, error } = await admin.rpc('get_dashboard_metrics', {
    p_company_id: cu.company_id,
    p_days: days,
  });

  if (error) {
    // optional: console.error('RPC error', error);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }

  return NextResponse.json(metrics ?? {});
}
