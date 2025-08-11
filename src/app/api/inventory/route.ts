// src/app/api/inventory/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const { supabase, user } = await requireUser(req);
    const companyId = requireCompanyId(user);

    const { searchParams } = new URL(req.url);
    const page = Math.max(1, parseInt(searchParams.get('page') ?? '1', 10));
    const limit = Math.min(100, Math.max(1, parseInt(searchParams.get('limit') ?? '10', 10)));
    const from = (page - 1) * limit;
    const to = from + limit - 1;

    // Items - Corrected to use the detailed view
    const { data: items, error: itemsErr } = await supabase
      .from('product_variants_with_details') // Using the detailed view
      .select('*')
      .eq('company_id', companyId)
      .order('product_title', { ascending: true })
      .range(from, to);

    if (itemsErr) throw itemsErr;

    // Count - Corrected to use the detailed view
    const { count, error: countErr } = await supabase
      .from('product_variants_with_details')
      .select('*', { count: 'exact', head: true })
      .eq('company_id', companyId);

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
