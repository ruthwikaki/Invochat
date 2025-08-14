
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAbcAnalysisFromDB, getSalesVelocityFromDB, getGrossMarginAnalysisFromDB } from "@/services/database";
import { AdvancedReportsClientPage, type AbcAnalysisItem } from "./advanced-reports-client-page";
import { getAuthContext } from "@/lib/auth-helpers";

export const dynamic = 'force-dynamic';

export default async function AdvancedReportsPage() {
    const { companyId } = await getAuthContext();

    const [abcAnalysisData, salesVelocityData, grossMarginData] = await Promise.all([
        getAbcAnalysisFromDB(companyId),
        getSalesVelocityFromDB(companyId, 90, 20),
        getGrossMarginAnalysisFromDB(companyId),
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
                    salesVelocityData={(salesVelocityData as any) || { fast_sellers: [], slow_sellers: [] }}
                    grossMarginData={(grossMarginData as any) || { products: [], summary: { total_revenue: 0, total_cogs: 0, total_gross_margin: 0, average_gross_margin: 0 } }}
                />
            </div>
        </AppPage>
    );
}
