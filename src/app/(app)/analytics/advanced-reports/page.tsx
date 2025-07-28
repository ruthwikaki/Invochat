

import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAuthContext } from "@/lib/auth-helpers";
import { getAbcAnalysisFromDB, getSalesVelocityFromDB, getGrossMarginAnalysisFromDB } from "@/services/database";
import { AdvancedReportsClientPage } from "./advanced-reports-client-page";

export const dynamic = 'force-dynamic';

export default async function AdvancedReportsPage() {

    const { companyId } = await getAuthContext();

    const [abcAnalysisData, salesVelocityData, grossMarginData] = await Promise.all([
        getAbcAnalysisFromDB(companyId),
        getSalesVelocityFromDB(companyId, 90, 10),
        getGrossMarginAnalysisFromDB(companyId)
    ]);

    return (
        <AppPage>
            <AppPageHeader
                title="Advanced Analytics"
                description="Go beyond basic reports with AI-driven analysis of your inventory."
            />
            <div className="mt-6">
                <AdvancedReportsClientPage
                    abcAnalysisData={abcAnalysisData || []}
                    salesVelocityData={salesVelocityData || { fast_sellers: [], slow_sellers: [] }}
                    grossMarginData={grossMarginData?.products || []}
                />
            </div>
        </AppPage>
    );
}

