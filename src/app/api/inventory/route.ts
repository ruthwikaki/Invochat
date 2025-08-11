// src/app/api/inventory/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';

export async function GET(req: NextRequest) {
  try {
    const { supabase, user } = await requireUser(req);
    const companyId = requireCompanyId(user);

    const { searchParams } = new URL(req.url);
    const page = Math.max(1, parseInt(searchParams.get('page') ?? '1', 10));
    const limit = Math.min(100, Math.max(1, parseInt(searchParams.get('limit') ?? '10', 10)));
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    // Items
    const { data: items, error: itemsErr } = await supabase
      .from('product_variants') // adjust if you use a view
      .select('*')
      .eq('company_id', companyId)
      .is('deleted_at', null)
      .order('updated_at', { ascending: false })
      .range(from, to);

    if (itemsErr) throw itemsErr;

    // Count
    const { count, error: countErr } = await supabase
      .from('product_variants')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId)
      .is('deleted_at', null);

    if (countErr) throw countErr;

    return NextResponse.json({
      items: items ?? [],
      totalCount: count ?? 0,
    });
  } catch (e: any) {
    const status = e instanceof ApiError ? e.status : 500;
    return NextResponse.json({ error: e.message || 'Internal Server Error' }, { status });
  }
}
