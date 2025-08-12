// src/app/api/analytics/dashboard/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';
import { getServiceRoleClient } from '@/lib/supabase/admin';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

function parseRangeToDays(input: string | null) {
  if (!input) return 30;
  const m = /^(\d+)d$/.exec(input.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  try {
    const { user } = await requireUser(req);
    const companyId = requireCompanyId(user);
    const { searchParams } = new URL(req.url);
    const days = parseRangeToDays(searchParams.get('range'));

    const admin = getServiceRoleClient();
    const { data: metrics, error } = await admin.rpc('get_dashboard_metrics', {
      p_company_id: companyId,
      p_days: days,
    });

    if (error) {
      console.error('RPC error', error);
      return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 });
    }

    const payload = Array.isArray(metrics) ? (metrics[0] ?? {}) : (metrics ?? {});
    return NextResponse.json(payload);

  } catch (e: any) {
    const status = e instanceof ApiError ? e.status : 500;
    return NextResponse.json({ error: e.message || 'Internal Server Error' }, { status });
  }
}
