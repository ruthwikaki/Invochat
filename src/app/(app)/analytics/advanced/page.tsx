import { Suspense } from 'react';
import ComprehensiveAnalyticsPage from '@/components/analytics/comprehensive-analytics-page';

// Loading component
function AnalyticsLoading() {
  return (
    <div className="p-6">
      <div className="animate-pulse space-y-4">
        <div className="h-8 bg-gray-200 rounded w-1/3"></div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {[1, 2, 3].map((i) => (
            <div key={i} className="h-32 bg-gray-200 rounded"></div>
          ))}
        </div>
        <div className="h-64 bg-gray-200 rounded"></div>
      </div>
    </div>
  );
}

// Server Component to fetch initial data
async function getInitialAnalyticsData() {
  try {
    // In a real app, you'd fetch from your API here
    // For now, return mock data
    return {
      totalRevenue: 125000,
      totalOrders: 1234,
      totalCustomers: 567,
      recentOrders: [],
      topProducts: [],
      lowStockAlerts: [],
      timestamp: new Date().toISOString()
    };
  } catch (error) {
    console.error('Failed to fetch initial analytics data:', error);
    return null;
  }
}

export default async function AdvancedAnalyticsPage() {
  const initialData = await getInitialAnalyticsData();

  return (
    <div className="min-h-screen bg-gray-50">
      <Suspense fallback={<AnalyticsLoading />}>
        <ComprehensiveAnalyticsPage initialData={initialData || undefined} />
      </Suspense>
    </div>
  );
}
