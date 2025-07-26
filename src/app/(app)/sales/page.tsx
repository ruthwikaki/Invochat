
import { getSalesData, exportSales, getSalesAnalytics } from '@/app/data-actions';
import { SalesClientPage } from './sales-client-page';
import { AppPageContainer } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25;

export default async function SalesPage({
  searchParams,
}: {
  searchParams?: {
    query?: string;
    page?: string;
  };
}) {
  const query = searchParams?.query || '';
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
    <AppPageContainer
      title="Sales History"
      description="View and manage all recorded sales orders."
    >
      <SalesClientPage
        initialSales={salesData.items}
        totalCount={salesData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        analyticsData={analyticsData}
        exportAction={handleExport}
      />
    </AppPageContainer>
  );
}
