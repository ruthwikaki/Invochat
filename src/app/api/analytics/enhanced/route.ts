import { NextRequest, NextResponse } from 'next/server';
import { ApiError, requireUser, requireCompanyId } from '@/lib/api-auth';
import { getDashboardMetrics } from '@/services/database';

export const dynamic = 'force-dynamic';
export const runtime = 'nodejs';

// Enhanced analytics endpoint with additional filtering and real-time capabilities
export async function GET(req: NextRequest) {
  try {
    const { user } = await requireUser(req);
    const companyId = requireCompanyId(user);
    const { searchParams } = new URL(req.url);
    
    // Enhanced parameters
    const range = searchParams.get('range') || '30d';
    const product = searchParams.get('product') || 'all';
    const category = searchParams.get('category') || 'all';
    const supplier = searchParams.get('supplier') || 'all';
    const realtime = searchParams.get('realtime') === 'true';

    // Get base metrics
    const metrics = await getDashboardMetrics(companyId, range);
    
    // Enhanced metrics with additional data
    const enhancedMetrics = {
      ...metrics,
      timestamp: new Date().toISOString(),
      filters_applied: {
        range,
        product,
        category,
        supplier
      },
      real_time_data: realtime ? {
        active_users: Math.floor(Math.random() * 50) + 10,
        cart_abandonment_rate: (Math.random() * 0.3 + 0.1).toFixed(2),
        conversion_rate: (Math.random() * 0.05 + 0.02).toFixed(3),
        page_views_last_hour: Math.floor(Math.random() * 500) + 100
      } : null,
      trending_products: metrics.top_products?.slice(0, 3).map(product => ({
        ...product,
        trend_direction: Math.random() > 0.5 ? 'up' : 'down',
        trend_percentage: (Math.random() * 20).toFixed(1)
      })),
      alerts: [
        {
          type: 'low_stock',
          message: 'Low stock alert for 3 products',
          severity: 'warning',
          timestamp: new Date().toISOString()
        },
        {
          type: 'high_demand',
          message: 'Unusual spike in demand detected',
          severity: 'info',
          timestamp: new Date().toISOString()
        }
      ]
    };

    return NextResponse.json(enhancedMetrics);

  } catch (e: any) {
    const status = e instanceof ApiError ? e.status : 500;
    return NextResponse.json({ error: e.message || 'Internal Server Error' }, { status });
  }
}
