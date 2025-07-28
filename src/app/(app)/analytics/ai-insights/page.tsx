
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { AiInsightsClientPage } from "./ai-insights-client-page";
import { getMarkdownSuggestions } from "@/ai/flows/markdown-optimizer-flow";
import { getBundleSuggestions } from "@/ai/flows/suggest-bundles-flow";
import { getPriceOptimizationSuggestions } from "@/ai/flows/price-optimization-flow";
import { findHiddenMoney } from "@/ai/flows/hidden-money-finder-flow";
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

    const generatePriceOptimization = async () => {
        'use server';
        const { companyId } = await getAuthContext();
        return getPriceOptimizationSuggestions({ companyId });
    };

    const generateHiddenMoney = async () => {
        'use server';
        const { companyId } = await getAuthContext();
        return findHiddenMoney({ companyId });
    }

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
                    generatePriceOptimizationAction={generatePriceOptimization}
                    generateHiddenMoneyAction={generateHiddenMoney}
                />
            </div>
        </AppPage>
    );
}
