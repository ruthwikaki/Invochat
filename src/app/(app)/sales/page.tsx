
import { getSalesData, exportSales, getSalesAnalytics } from '@/app/data-actions';
import { SalesClientPage } from './sales-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import type { Order, SalesAnalytics } from '@/types';

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
                initialSales={salesData.items as Order[]}
                totalCount={salesData.totalCount}
                itemsPerPage={ITEMS_PER_PAGE}
                analyticsData={analyticsData as SalesAnalytics}
                exportAction={handleExport}
            />
        </div>
    </AppPage>
  );
}
