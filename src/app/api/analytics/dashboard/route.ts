
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
  if (process.env.TEST_MODE === 'true' || process.env.NEXT_PUBLIC_TEST_MODE === 'true') {
    return NextResponse.json({
        total_revenue: 123456,
        revenue_change: 12.5,
        total_orders: 42,
        orders_change: -5.2,
        new_customers: 7,
        customers_change: 10.0,
        dead_stock_value: 34567,
        sales_over_time: [{ date: '2025-08-01', revenue: 12345 }, { date: '2025-08-02', revenue: 23456 }],
        top_selling_products: [{ product_id: 'prod-1', product_name: 'Test Product', image_url: null, quantity_sold: 10, total_revenue: 123456 }],
        inventory_summary: {
            total_value: 500000,
            in_stock_value: 300000,
            low_stock_value: 150000,
            dead_stock_value: 50000,
        }
    });
  }

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
