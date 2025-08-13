
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAdvancedAbcReport, getAdvancedSalesVelocityReport, getAdvancedGrossMarginReport } from "@/app/data-actions";
import { AdvancedReportsClientPage, type SalesVelocityItem, type GrossMarginItem, type AbcAnalysisItem } from "./advanced-reports-client-page";
import type { Json } from "@/types/database.types";

export const dynamic = 'force-dynamic';

export default async function AdvancedReportsPage() {

    const [abcAnalysisData, salesVelocityData, grossMarginData] = await Promise.all([
        getAdvancedAbcReport(),
        getAdvancedSalesVelocityReport(),
        getAdvancedGrossMarginReport(),
    ]);

    return (
        <AppPage>
            <AppPageHeader
                title="Advanced Analytics"
                description="Go beyond basic reports with AI-driven analysis of your inventory."
            />
            <div className="mt-6">
                <AdvancedReportsClientPage
                    abcAnalysisData={(abcAnalysisData as AbcAnalysisItem[]) || []}
                    salesVelocityData={(salesVelocityData as { fast_sellers: SalesVelocityItem[], slow_sellers: SalesVelocityItem[] }) || { fast_sellers: [], slow_sellers: [] }}
                    grossMarginData={(grossMarginData as any) || { products: [], summary: { total_revenue: 0, total_cogs: 0, total_gross_margin: 0, average_gross_margin: 0 } }}
                />
            </div>
        </AppPage>
    );
}
