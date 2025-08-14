

import { getInventoryTurnoverReportData } from '@/app/data-actions';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { InventoryTurnoverClientPage } from './inventory-turnover-client-page';
import type { TurnoverReport } from './inventory-turnover-client-page';

export const dynamic = 'force-dynamic';

export default async function InventoryTurnoverPage() {
    const reportData = await getInventoryTurnoverReportData();

    // Ensure reportData is not null and conforms to the expected type
    const safeReportData: TurnoverReport = (reportData as TurnoverReport) || {
        turnover_rate: 0,
        total_cogs: 0,
        average_inventory_value: 0,
        period_days: 90,
    };

    return (
        <AppPage>
            <AppPageHeader
                title="Inventory Turnover"
                description="Analyze how efficiently your inventory is being sold and replenished."
            />
            <InventoryTurnoverClientPage report={safeReportData} />
        </AppPage>
    );
}

    
