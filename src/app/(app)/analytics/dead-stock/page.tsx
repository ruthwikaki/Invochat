
import { getDeadStockPageData, markdownOptimizerFlow } from '@/app/(app)/analytics/dead-stock/actions';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { DeadStockClientPage } from './dead-stock-client-page';
import { getMarkdownSuggestions } from '@/ai/flows/markdown-optimizer-flow';
import { getAuthContext } from '@/lib/auth-helpers';

export const dynamic = 'force-dynamic';

export default async function DeadStockPage() {
    const deadStockData = await getDeadStockPageData();

    // The server component now needs to be able to pass down the server action
    // to the client component.
    const handleGeneratePlan = async () => {
        'use server';
        const { companyId } = await getAuthContext();
        // The tool returns the flow, so we call it directly.
        return getMarkdownSuggestions.func({ companyId });
    }

    return (
        <AppPage>
            <AppPageHeader
                title="Dead Stock Analysis"
                description="Identify money trapped in slow-moving inventory."
            />
            <DeadStockClientPage 
                initialData={deadStockData} 
                generateMarkdownPlanAction={handleGeneratePlan}
            />
        </AppPage>
    );
}
