
import { getReorderReport } from '@/app/data-actions';
import { ReorderClientPage } from './reorder-client-page';
import { AppPageHeader } from '@/components/ui/page';

export const dynamic = 'force-dynamic';

export default async function ReorderingPage() {
    const suggestions = await getReorderReport();
    
    return (
        <>
            <AppPageHeader 
                title="Reorder Suggestions"
                description="Review AI-powered suggestions for products that need restocking."
            />
            <ReorderClientPage initialSuggestions={suggestions} />
        </>
    )
}
