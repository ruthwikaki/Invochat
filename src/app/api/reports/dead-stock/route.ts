// src/app/api/reports/dead-stock/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const { supabase, user } = await requireUser(req);
    const companyId = requireCompanyId(user);

    const { searchParams } = new URL(req.url);
    const days = parseInt(searchParams.get('days') ?? '90', 10);

    const { data, error } = await supabase.rpc('get_dead_stock_report', {
      p_company_id: companyId,
      p_days: isNaN(days) ? 90 : days,
    });
    if (error) throw error;

    // data is already { deadStockItems, totalValue }
    return NextResponse.json(data ?? { deadStockItems: [], totalValue: 0 });
  } catch (e: any) {
    const status = e instanceof ApiError ? e.status : 500;
    return NextResponse.json({ error: e.message || 'Internal Server Error' }, { status });
  }
}
