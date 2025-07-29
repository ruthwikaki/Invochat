
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAdvancedAbcReport, getAdvancedSalesVelocityReport, getAdvancedGrossMarginReport } from "@/app/data-actions";
import { AdvancedReportsClientPage } from "./advanced-reports-client-page";

export const dynamic = 'force-dynamic';

export default async function AdvancedReportsPage() {

    const abcAnalysisData = await getAdvancedAbcReport();

    return (
        <AppPage>
            <AppPageHeader
                title="Advanced Analytics"
                description="Go beyond basic reports with AI-driven analysis of your inventory."
            />
            <div className="mt-6">
                <AdvancedReportsClientPage
                    abcAnalysisData={abcAnalysisData || []}
                />
            </div>
        </AppPage>
    );
}
