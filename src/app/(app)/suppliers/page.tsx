
import { getSupplierPerformanceReportData } from '@/app/data-actions';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { SupplierPerformanceClientPage } from './supplier-performance-client-page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';

export const dynamic = 'force-dynamic';

export default async function SuppliersPage() {
    const reportData = await getSupplierPerformanceReportData();

    return (
        <AppPage>
            <AppPageHeader
                title="Supplier Performance"
                description="Analyze which of your suppliers are the most reliable and profitable."
            >
                 <Button asChild>
                    <Link href="/suppliers/new">Add Supplier</Link>
                </Button>
            </AppPageHeader>
            <div className="mt-6">
                <SupplierPerformanceClientPage initialData={reportData} />
            </div>
        </AppPage>
    );
}
