
import { getSuppliersDataFromDB } from '@/services/database';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { SuppliersClientPage } from './suppliers-client-page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';
import { getAuthContext } from '@/lib/auth-helpers';

export const dynamic = 'force-dynamic';

export default async function SuppliersPage() {
    const { companyId } = await getAuthContext();
    const suppliers = await getSuppliersDataFromDB(companyId);

    return (
        <AppPage>
            <AppPageHeader
                title="Suppliers"
                description="Manage your list of suppliers and vendors."
            >
                 <Button asChild>
                    <Link href="/suppliers/new">Add Supplier</Link>
                </Button>
            </AppPageHeader>
            <div className="mt-6">
                <SuppliersClientPage initialSuppliers={suppliers} />
            </div>
        </AppPage>
    );
}
