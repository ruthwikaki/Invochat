
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { AiInsightsClientPage } from "./ai-insights-client-page";
import { getMarkdownSuggestions } from "@/ai/flows/markdown-optimizer-flow";
import { getBundleSuggestions } from "@/ai/flows/suggest-bundles-flow";
import { getAuthContext } from "@/lib/auth-helpers";

export const dynamic = 'force-dynamic';

export default function AiInsightsPage() {
    
    const generateMarkdownPlan = async () => {
        'use server';
        const { companyId } = await getAuthContext();
        return getMarkdownSuggestions({ companyId });
    };

    const generateBundleSuggestions = async (count: number) => {
        'use server';
        const { companyId } = await getAuthContext();
        return getBundleSuggestions({ companyId, count });
    };

    return (
        <AppPage>
            <AppPageHeader
                title="AI-Powered Insights"
                description="Leverage AI to discover hidden opportunities and optimize your inventory."
            />
            <div className="mt-6">
                <AiInsightsClientPage 
                    generateMarkdownPlanAction={generateMarkdownPlan}
                    generateBundleSuggestionsAction={generateBundleSuggestions}
                />
            </div>
        </AppPage>
    );
}
