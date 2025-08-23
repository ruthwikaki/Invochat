import { NextRequest, NextResponse } from 'next/server';
import { getSalesFromDB, getUnifiedInventoryFromDB } from '@/services/database';
import { requireUser } from '@/lib/api-auth';

export async function GET(request: NextRequest) {
  try {
    // Authenticate request
    const { user } = await requireUser(request);
    const companyId = user.user_metadata?.company_id;
    
    if (!companyId) {
      return NextResponse.json({ error: 'Company ID not found' }, { status: 400 });
    }
    
    // Fetch real-time analytics data
    const [salesData, inventoryData] = await Promise.all([
      getSalesFromDB(companyId, { offset: 0, limit: 1000 }),
      getUnifiedInventoryFromDB(companyId, { offset: 0, limit: 1000 })
    ]);

    // Calculate real-time metrics
    const totalRevenue = salesData.items.reduce((sum: number, item: any) => sum + (item.total_value || 0), 0);
    const totalOrders = salesData.items.length;
    const totalCustomers = new Set(salesData.items.map((item: any) => item.customer_id).filter(Boolean)).size;

    // Get recent orders (last 10)
    const recentOrders = salesData.items
      .sort((a: any, b: any) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime())
      .slice(0, 10)
      .map((order: any) => ({
        id: order.id,
        customer_name: order.customer_name || 'Unknown Customer',
        total_value: order.total_value || 0,
        status: order.status || 'pending',
        created_at: order.created_at
      }));

    // Get top products by revenue
    const productRevenue = new Map();
    salesData.items.forEach((order: any) => {
      if (order.product_name && order.total_value) {
        const current = productRevenue.get(order.product_name) || 0;
        productRevenue.set(order.product_name, current + order.total_value);
      }
    });

    const topProducts = Array.from(productRevenue.entries())
      .sort(([, a]: [string, number], [, b]: [string, number]) => b - a)
      .slice(0, 5)
      .map(([name, revenue]: [string, number]) => ({
        name,
        revenue,
        formatted_revenue: new Intl.NumberFormat('en-US', {
          style: 'currency',
          currency: 'USD'
        }).format(revenue)
      }));

    // Get low stock alerts
    const lowStockAlerts = inventoryData.items
      .filter((item: any) => {
        const currentStock = item.current_quantity || 0;
        const reorderPoint = item.reorder_point || 10;
        return currentStock <= reorderPoint;
      })
      .slice(0, 10)
      .map((item: any) => ({
        sku: item.sku,
        product_name: item.product_name,
        current_quantity: item.current_quantity || 0,
        reorder_point: item.reorder_point || 10,
        supplier: item.supplier || 'Unknown'
      }));

    const analyticsData = {
      totalRevenue: Math.round(totalRevenue * 100) / 100,
      totalOrders,
      totalCustomers,
      recentOrders,
      topProducts,
      lowStockAlerts,
      timestamp: new Date().toISOString()
    };

    return NextResponse.json(analyticsData);

  } catch (error) {
    console.error('Realtime analytics API error:', error);
    return NextResponse.json(
      { error: 'Failed to fetch analytics data' },
      { status: 500 }
    );
  }
}
