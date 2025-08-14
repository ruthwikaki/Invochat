
// src/app/api/analytics/dashboard/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';
import { getDashboardMetrics } from '@/services/database';

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

    const metrics = await getDashboardMetrics(companyId, String(days));

    const payload = Array.isArray(metrics) ? (metrics[0] ?? {}) : (metrics ?? {});
    return NextResponse.json(payload);

  } catch (e: any) {
    const status = e instanceof ApiError ? e.status : 500;
    return NextResponse.json({ error: e.message || 'Internal Server Error' }, { status });
  }
}
