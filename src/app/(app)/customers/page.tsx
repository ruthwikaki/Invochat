
import { getCustomersData } from '@/app/data-actions';
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
  const customerData = await getCustomersData({ query, page: currentPage });

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Customers"
        description="View and manage your customer list."
      />
      <CustomersClientPage 
        initialCustomers={customerData.items}
        totalCount={customerData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
      />
    </AppPage>
  );
}
