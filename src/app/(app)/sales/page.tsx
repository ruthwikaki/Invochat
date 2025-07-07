
import { getSales, exportSales } from '@/app/data-actions';
import { SalesClientPage } from '@/components/sales/sales-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';
import Link from 'next/link';

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

  const salesData = await getSales({ query, page, limit: ITEMS_PER_PAGE });

  const handleExport = async () => {
    'use server';
    return exportSales({ query });
  }

  return (
    <AppPage>
      <AppPageHeader
        title="Sales History"
        description="View and manage all recorded sales."
      >
        <Button asChild>
          <Link href="/sales/quick-sale">
            <Plus className="mr-2 h-4 w-4" />
            Record New Sale
          </Link>
        </Button>
      </AppPageHeader>
      <SalesClientPage
        initialSales={salesData.items}
        totalCount={salesData.totalCount}
        itemsPerPage={ITEMS_PER_PAGE}
        exportAction={handleExport}
      />
    </AppPage>
  );
}
