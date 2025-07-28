
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getFeedbackData } from "@/app/data-actions";
import { AiPerformanceClientPage } from "./ai-performance-client-page";

export const dynamic = 'force-dynamic';

const ITEMS_PER_PAGE = 25;

export default async function AiPerformancePage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
    const page = Number(searchParams?.page) || 1;
    const query = searchParams?.query?.toString() || '';

    const feedbackData = await getFeedbackData({ page, limit: ITEMS_PER_PAGE, query });
    
    return (
        <AppPage>
            <AppPageHeader
                title="AI Performance & Feedback"
                description="Review user feedback on AI responses to monitor quality and identify areas for improvement."
            />
            <div className="mt-6">
                <AiPerformanceClientPage 
                    initialData={feedbackData.items}
                    totalCount={feedbackData.totalCount}
                    itemsPerPage={ITEMS_PER_PAGE}
                />
            </div>
        </AppPage>
    );
}
