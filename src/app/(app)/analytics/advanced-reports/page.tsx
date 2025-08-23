
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAdvancedAbcReport, getAdvancedSalesVelocityReport, getAdvancedGrossMarginReport } from "@/app/data-actions";
import { AdvancedReportsClientPage } from "./advanced-reports-client-page";

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
                    abcAnalysisData={abcAnalysisData ? abcAnalysisData.map((item: any) => ({
                        sku: item.sku,
                        product_name: item.product_name,
                        revenue: item.revenue,
                        cumulative_revenue_percentage: item.cumulative_percentage / 100,
                        abc_category: item.category as 'A' | 'B' | 'C'
                    })) : []}
                    salesVelocityData={(salesVelocityData as any) || { fast_sellers: [], slow_sellers: [] }}
                    grossMarginData={(grossMarginData as any) || { products: [], summary: { total_revenue: 0, total_cogs: 0, total_gross_margin: 0, average_gross_margin: 0 } }}
                />
            </div>
        </AppPage>
    );
}
