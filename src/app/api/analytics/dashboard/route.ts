// src/app/api/analytics/dashboard/route.ts
import { NextRequest, NextResponse } from 'next/server';
import { createClient } from '@supabase/supabase-js';
import type { Database } from '@/types/database.types';

export const runtime = 'nodejs';       // force Node runtime (avoids Edge bundling issues)
export const dynamic = 'force-dynamic';

function daysFromRange(range: string | null): number {
  if (!range) return 30;
  const m = /^(\d+)\s*d$/i.exec(range.trim());
  return m ? Math.max(1, parseInt(m[1], 10)) : 30;
}

export async function GET(req: NextRequest) {
  const authHeader = req.headers.get('authorization') ?? req.headers.get('Authorization');
  if (!authHeader?.toLowerCase().startsWith('bearer ')) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const accessToken = authHeader.split(/\s+/)[1];
  const days = daysFromRange(new URL(req.url).searchParams.get('range'));

  const url  = process.env.NEXT_PUBLIC_SUPABASE_URL!;
  const anon = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!;
  const service = process.env.SUPABASE_SERVICE_ROLE_KEY; // optional but preferred for internal reads

  // Client with the user's token (for auth.getUser and RPC under RLS)
  const userClient = createClient<Database>(url, anon, {
    global: { headers: { Authorization: `Bearer ${accessToken}` } },
  });

  // Admin client (bypasses RLS) for safe internal lookups like company mapping
  const admin = service
    ? createClient<Database>(url, service, { auth: { persistSession: false } })
    : null;

  // 1) Identify user
  const { data: userRes, error: userErr } = await userClient.auth.getUser();
  if (userErr || !userRes?.user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  const userId = userRes.user.id;

  // 2) Resolve company id (admin first, then fallback to user client; then owner; then “any”)
  let companyId: string | null = null;

  // company_users mapping
  if (!companyId) {
    const client = admin ?? userClient;
    const { data, error } = await client
      .from('company_users')
      .select('company_id')
      .eq('user_id', userId)
      .limit(1)
      .maybeSingle();
    if (!error && data?.company_id) companyId = data.company_id as string;
  }

  // companies.owner_id fallback
  if (!companyId) {
    const client = admin ?? userClient;
    const { data, error } = await client
      .from('companies')
      .select('id')
      .eq('owner_id', userId)
      .limit(1)
      .maybeSingle();
    if (!error && data?.id) companyId = data.id as string;
  }

  // last-ditch: pick any company (useful in seeded test DBs)
  if (!companyId) {
    const client = admin ?? userClient;
    const { data, error } = await client
      .from('companies')
      .select('id')
      .limit(1)
      .maybeSingle();
    if (!error && data?.id) companyId = data.id as string;
  }

  if (!companyId) {
    return NextResponse.json({ error: 'No company found for user' }, { status: 403 });
  }

  // 3) Call RPC
  const { data: rpc, error: rpcErr } = await userClient.rpc('get_dashboard_metrics', {
    p_company_id: companyId,
    p_days: days,
  });

  if (rpcErr) {
    // Surface DB error for debugging during tests
    return NextResponse.json({ error: rpcErr.message }, { status: 500 });
  }

  const r: any = rpc ?? {};
  return NextResponse.json({
    total_orders: r.total_orders ?? 0,
    total_revenue: r.total_revenue ?? 0,
    total_customers: r.total_customers ?? 0,
    inventory_count: r.inventory_count ?? 0,
    sales_series: r.sales_series ?? [],     // test expects this key name
    top_products: r.top_products ?? [],     // test expects this key name
    inventory_summary: r.inventory_summary ?? {
      total_value: 0, in_stock_value: 0, low_stock_value: 0, dead_stock_value: 0,
    },
    revenue_change: r.revenue_change ?? 0,
    orders_change: r.orders_change ?? 0,
    customers_change: r.customers_change ?? 0,
    dead_stock_value: r.dead_stock_value ?? 0,
  });
}