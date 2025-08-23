import { Suspense } from 'react';
import EnhancedForecastingDashboard from '@/components/analytics/enhanced-demand-forecasting-dashboard';

export default function EnhancedForecastingPage() {
  return (
    <div className="container mx-auto py-8">
      <Suspense fallback={
        <div className="flex items-center justify-center h-96">
          <div className="animate-spin rounded-full h-32 w-32 border-b-2 border-primary"></div>
        </div>
      }>
        <EnhancedForecastingDashboard />
      </Suspense>
    </div>
  );
}
