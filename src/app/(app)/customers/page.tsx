

import { getCustomersData, exportCustomers, getCustomerAnalytics } from '@/app/data-actions';
import { CustomersClientPage } from './customers-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import type { Customer } from '@/types';

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
  const page = Number(searchParams?.page) || 1;

  // Fetch data in parallel for better performance
  const [customersData, analyticsData] = await Promise.all([
    getCustomersData({ query, page, limit: ITEMS_PER_PAGE }),
    getCustomerAnalytics(),
  ]);

  const handleExport = async () => {
    'use server';
    return exportCustomers({ query });
  }

  return (
    <AppPage>
      <AppPageHeader
        title="Customers"
        description="View and manage your customer list and analytics."
      />
      <CustomersClientPage
        initialCustomers={customersData.items as Customer[]}
        totalCount={customersData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        analyticsData={analyticsData}
        exportAction={handleExport}
      />
    </AppPage>
  );
}
