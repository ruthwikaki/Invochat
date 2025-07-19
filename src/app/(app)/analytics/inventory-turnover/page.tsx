import { getInventoryTurnoverReportData } from '@/app/data-actions';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { InventoryTurnoverClientPage } from './inventory-turnover-client-page';

export const dynamic = 'force-dynamic';

export default async function InventoryTurnoverPage() {
    const reportData = await getInventoryTurnoverReportData();

    return (
        <AppPage>
            <AppPageHeader
                title="Inventory Turnover"
                description="Analyze how efficiently your inventory is being sold and replenished."
            />
            <InventoryTurnoverClientPage report={reportData} />
        </AppPage>
    );
}
