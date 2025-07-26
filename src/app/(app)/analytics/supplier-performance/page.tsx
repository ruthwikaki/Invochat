
import { getSupplierPerformanceReportData } from '@/app/data-actions';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { SupplierPerformanceClientPage } from './supplier-performance-client-page';

export const dynamic = 'force-dynamic';

export default async function SupplierPerformancePage() {
    const reportData = await getSupplierPerformanceReportData();

    return (
        <AppPage>
            <AppPageHeader
                title="Supplier Performance"
                description="Analyze which of your suppliers are the most reliable and profitable."
            />
            <SupplierPerformanceClientPage initialData={reportData} />
        </AppPage>
    );
}
