
import { getReorderReport } from '@/app/(app)/analytics/reordering/actions';
import { ReorderClientPage } from './reorder-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function ReorderingPage() {
    const suggestions = await getReorderReport();

    return (
        <AppPage>
            <AppPageHeader
                title="Reorder Suggestions"
                description="Review AI-powered suggestions for products that need restocking."
            />
            <ReorderClientPage initialSuggestions={suggestions} />
        </AppPage>
    )
}
