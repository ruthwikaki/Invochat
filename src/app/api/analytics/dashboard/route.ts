
// src/app/api/analytics/dashboard/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { getDashboardMetrics } from '@/services/database';

export const runtime = 'nodejs';

function parseRangeToDays(input: string | null): number {
  if (!input) return 30;
  const m = /^(\d+)\s*d$/.exec(input.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  try {
    const url = new URL(req.url);
    const days = parseRangeToDays(url.searchParams.get('range'));

    // Try Bearer first (works in Playwright/API tests)
    const authHeader =
      req.headers.get('authorization') ?? req.headers.get('Authorization');

    const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL!;
    const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;

    const supabase = createClient(supabaseUrl, anonKey, {
      global: authHeader ? { headers: { Authorization: authHeader } } : {},
    });

    const { data: userRes, error: userErr } = await supabase.auth.getUser();
    if (userErr || !userRes?.user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    // Find the user's company using service role (DB reads)
    const admin = getServiceRoleClient();
    const { data: cu, error: cuErr } = await admin
      .from('company_users')
      .select('company_id')
      .eq('user_id', userRes.user.id)
      .limit(1)
      .maybeSingle();

    if (cuErr || !cu?.company_id) {
      return NextResponse.json({ error: 'No company found' }, { status: 403 });
    }

    // Use your existing DB util which calls the SQL function
    const metrics = await getDashboardMetrics(cu.company_id, days);
    return NextResponse.json(metrics, { status: 200 });
  } catch (err) {
    console.error('analytics/dashboard error', err);
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
  }
}
