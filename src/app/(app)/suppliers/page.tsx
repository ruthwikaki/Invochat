
import { getSuppliersData } from '@/app/data-actions';
import { SuppliersClientPage } from '@/components/suppliers/suppliers-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';
import Link from 'next/link';

export default async function SuppliersPage() {
  const suppliers = await getSuppliersData();

  return (
    <AppPage>
      <AppPageHeader title="Suppliers">
        <Button asChild>
          <Link href="/suppliers/new">
            <Plus className="mr-2 h-4 w-4" />
            New Supplier
          </Link>
        </Button>
      </AppPageHeader>
      <SuppliersClientPage initialSuppliers={suppliers} />
    </AppPage>
  );
}
