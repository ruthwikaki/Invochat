
'use client';

import { ImporterClientPage } from '@/components/import/importer-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function ImportPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Data Importer"
        description="Upload CSV files to populate your database tables."
      />
      <ImporterClientPage />
    </AppPage>
  );
}
