
'use server';

import { getDeadStockReportFromDB, getSettings } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';
import { markdownOptimizerFlow } from '@/ai/flows/markdown-optimizer-flow';

export async function getDeadStockPageData() {
    const { companyId } = await getAuthContext();
    const settings = await getSettings(companyId);
    const deadStockData = await getDeadStockReportFromDB(companyId);
    return {
        ...deadStockData,
        deadStockDays: settings.dead_stock_days
    };
}

// Re-exporting the flow to be used as a server action
export { markdownOptimizerFlow };
