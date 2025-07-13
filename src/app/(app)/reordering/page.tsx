

import { AppPage, AppPageHeader } from '@/components/ui/page';
import { getReorderReport, getCompanySettings } from '@/app/data-actions';
import { ReorderClientPage } from '@/components/reordering/reorder-client-page';

export const dynamic = 'force-dynamic';

export default async function ReorderingPage() {
  const [suggestions, settings] = await Promise.all([
    getReorderReport(),
    getCompanySettings(),
  ]);
  
  return (
     <AppPage>
        <AppPageHeader 
            title="Reorder Suggestions"
            description="AI-powered recommendations for what to order next, based on sales velocity and seasonality."
        />
        <ReorderClientPage initialSuggestions={suggestions} companyName={settings.company_name || 'Your Company'} />
    </AppPage>
  );
}
