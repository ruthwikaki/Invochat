
import { getSalesData, exportSales, getSalesAnalytics } from '@/app/data-actions';
import { SalesClientPage } from './sales-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
<<<<<<< HEAD
import type { SalesAnalytics as SalesAnalyticsType } from '@/types';
=======
import type { SalesAnalytics } from '@/types';
>>>>>>> 6168ea0773980b7de6d6d789337dd24b18126f79

const ITEMS_PER_PAGE = 25;

export default async function SalesPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const query = searchParams?.query?.toString() || '';
  const page = Number(searchParams?.page) || 1;

  // Fetch data in parallel for better performance
  const [salesData, analyticsData] = await Promise.all([
    getSalesData({ query, page, limit: ITEMS_PER_PAGE }),
    getSalesAnalytics(),
  ]);

  const handleExport = async (params: { query: string }) => {
    'use server';
    return exportSales(params);
  }

  return (
    <AppPage>
        <AppPageHeader
            title="Sales History"
            description="View and manage all recorded sales orders."
        />
        <div className="mt-6">
            <SalesClientPage
                initialSales={salesData.items}
                totalCount={salesData.totalCount}
                itemsPerPage={ITEMS_PER_PAGE}
<<<<<<< HEAD
                analyticsData={analyticsData as SalesAnalyticsType}
=======
                analyticsData={analyticsData as SalesAnalytics}
>>>>>>> 6168ea0773980b7de6d6d789337dd24b18126f79
                exportAction={handleExport}
            />
        </div>
    </AppPage>
  );
}

    