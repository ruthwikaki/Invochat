
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Upload } from 'lucide-react';
import { ImporterClientPage } from '@/components/import/importer-client-page';

export default function ImportPage() {
  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
            <SidebarTrigger className="md:hidden" />
            <div>
                <h1 className="text-2xl font-semibold flex items-center gap-2">
                    <Upload className="h-6 w-6" />
                    Data Importer
                </h1>
                <p className="text-muted-foreground text-sm">
                    Upload CSV files to populate your database tables.
                </p>
            </div>
        </div>
      </div>
      <ImporterClientPage />
    </div>
  );
}
