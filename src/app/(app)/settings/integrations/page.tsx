
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { IntegrationsClientPage } from '@/features/integrations/components/IntegrationsPage';

export default function IntegrationsPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Integrations"
        description="Connect your other business tools to sync data automatically."
      />
      <IntegrationsClientPage />
    </AppPage>
  );
}
