

import { AppPage, AppPageHeader } from '@/components/ui/page';
import { getReorderReport } from '@/app/data-actions';
import { ReorderClientPage } from '@/components/reordering/reorder-client-page';

export const dynamic = 'force-dynamic';

export default async function ReorderingPage() {
  const suggestions = await getReorderReport();
  
  return (
     <AppPage>
        <AppPageHeader 
            title="Reorder Suggestions"
            description="AI-powered recommendations for what to order next, based on sales velocity and seasonality."
        />
        <ReorderClientPage initialSuggestions={suggestions} />
    </AppPage>
  );
}
