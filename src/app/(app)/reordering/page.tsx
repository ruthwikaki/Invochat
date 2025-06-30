
import { getReorderSuggestions } from '@/app/data-actions';
import { ReorderClientPage } from '@/components/reordering/reorder-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function ReorderingPage() {
  const suggestions = await getReorderSuggestions();

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Reorder Suggestions"
        description="AI-powered suggestions for what to order next based on sales velocity and stock levels."
      />
      <ReorderClientPage initialSuggestions={suggestions} />
    </AppPage>
  );
}
