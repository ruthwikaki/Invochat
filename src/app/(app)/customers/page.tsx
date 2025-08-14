
import { getCustomersData, exportCustomers, getCustomerAnalytics } from '@/app/data-actions';
import { CustomersClientPage } from './customers-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import type { Customer, CustomerAnalytics as CustomerAnalyticsType } from '@/types';

const ITEMS_PER_PAGE = 25;

export default async function CustomersPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
  const query = searchParams?.query?.toString() || '';
  const page = Number(searchParams?.page) || 1;

  // Fetch data in parallel for better performance
  const [customersData, analyticsData] = await Promise.all([
    getCustomersData({ query, page, limit: ITEMS_PER_PAGE }),
    getCustomerAnalytics(),
  ]);

  const handleExport = async (params: {query: string}) => {
    'use server';
    return exportCustomers({ query: params.query });
  }

  return (
    <AppPage>
        <AppPageHeader
            title="Customer Intelligence"
            description="Analyze customer behavior and identify your most valuable segments."
        />
        <div className="mt-6">
            <CustomersClientPage
                initialCustomers={customersData.items as Customer[]}
                totalCount={customersData.totalCount}
                itemsPerPage={ITEMS_PER_PAGE}
                analyticsData={analyticsData as CustomerAnalyticsType}
                exportAction={handleExport}
            />
        </div>
    </AppPage>
  );
}
