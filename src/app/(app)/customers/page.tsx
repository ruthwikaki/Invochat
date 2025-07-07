
import { getCustomersData, getCustomerAnalytics, exportCustomers } from '@/app/data-actions';
import { CustomersClientPage } from '@/components/customers/customers-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

const ITEMS_PER_PAGE = 25;

export default async function CustomersPage({
    searchParams,
}: {
    searchParams?: {
        query?: string;
        page?: string;
    };
}) {
  const query = searchParams?.query || '';
  const currentPage = Number(searchParams?.page) || 1;

  const [customerData, analyticsData] = await Promise.all([
    getCustomersData({ query, page: currentPage }),
    getCustomerAnalytics(),
  ]);

  const handleExport = async () => {
    'use server';
    return exportCustomers({ query });
  }

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Customer Analytics"
        description="Analyze your customer base to find key insights and trends."
      />
      <CustomersClientPage
        initialCustomers={customerData.items}
        totalCount={customerData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        analyticsData={analyticsData}
        exportAction={handleExport}
      />
    </AppPage>
  );
}
