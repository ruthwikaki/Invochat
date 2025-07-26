
import { getSuppliersData } from '@/app/data-actions';
import { SuppliersClientPage } from './suppliers-client-page';
import { AppPageContainer } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';

export default async function SuppliersPage() {
    const suppliers = await getSuppliersData();
    return (
        <AppPageContainer
            title="Suppliers"
            description="Manage your vendors and their contact information."
            headerContent={(
                <Button asChild>
                    <Link href="/suppliers/new">Add Supplier</Link>
                </Button>
            )}
        >
            <SuppliersClientPage initialSuppliers={suppliers} />
        </AppPageContainer>
    )
}
