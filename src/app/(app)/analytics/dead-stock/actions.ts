

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

export async function generateMarkdownPlan() {
    'use server';
    const { companyId } = await getAuthContext();
    return markdownOptimizerFlow({ companyId });
}
