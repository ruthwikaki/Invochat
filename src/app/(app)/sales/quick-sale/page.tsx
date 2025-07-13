

// This page is obsolete and will be removed.
// Sales data should now be synced from an e-commerce platform integration.

import { AppPage, AppPageHeader } from "@/components/ui/page";

export default function QuickSalePage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Quick Sale"
        description="This feature has been removed."
      />
      <div className="text-center p-8 border-2 border-dashed rounded-lg">
        <p className="text-muted-foreground">
            Sales should now be synced from your e-commerce platform via the Integrations page.
        </p>
      </div>
    </AppPage>
  )
}
