import { getReorderReport } from '@/app/data-actions';
import { ReorderClientPage } from './reorder-client-page';
import { AppPageHeader } from '@/components/ui/page';

export default async function ReorderingPage() {
    const suggestions = await getReorderReport();
    
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Reorder Suggestions"
                description="Review AI-powered suggestions for products that need restocking."
            />
            <ReorderClientPage initialSuggestions={suggestions} />
        </div>
    )
}
