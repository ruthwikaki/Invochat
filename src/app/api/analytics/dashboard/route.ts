import { NextRequest, NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { getDashboardMetrics } from '@/services/database';

export const runtime = 'nodejs';
export const dynamic = 'force-dynamic';

function parseRangeToDays(input: string | null): number {
  if (!input) return 30;
  const m = /^(\d+)\s*d$/i.exec(input.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  try {
    const url = new URL(req.url);
    const days = parseRangeToDays(url.searchParams.get('range'));

    const authHeader =
      req.headers.get('authorization') ?? req.headers.get('Authorization');
    if (!authHeader?.toLowerCase().startsWith('bearer ')) {
      return NextResponse.json({ error: 'Unauthorized: Missing Bearer token' }, { status: 401 });
    }
    const accessToken = authHeader.split(/\s+/)[1];

    const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

    // Validate the incoming token with Supabase auth
    const userResponse = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
      headers: { apikey: ANON_KEY, Authorization: `Bearer ${accessToken}` },
    });

    if (!userResponse.ok) {
      return NextResponse.json({ error: 'Unauthorized: Invalid token' }, { status: 401 });
    }
    const user = await userResponse.json();
    if (!user?.id) {
      return NextResponse.json({ error: 'Unauthorized: User not found for token' }, { status: 401 });
    }

    // Find the user's company using service role (DB reads)
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

    // Use your existing DB util which calls the SQL function
    const metrics = await getDashboardMetrics(cu.company_id, days);
    return NextResponse.json(metrics);
    
  } catch (err: any) {
    console.error('analytics/dashboard error', err);
    return NextResponse.json({ error: 'Internal Server Error', details: err.message }, { status: 500 });
  }
}
