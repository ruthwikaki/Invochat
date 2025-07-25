
import { getSuppliersData } from '@/app/data-actions';
import { SuppliersClientPage } from './suppliers-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';

export default async function SuppliersPage() {
    const suppliers = await getSuppliersData();
    return (
        <AppPage>
            <AppPageHeader
                title="Suppliers"
                description="Manage your vendors and their contact information."
            >
                <Button asChild>
                    <Link href="/suppliers/new">Add Supplier</Link>
                </Button>
            </AppPageHeader>
            <div className="mt-6">
                <SuppliersClientPage initialSuppliers={suppliers} />
            </div>
        </AppPage>
    )
}
