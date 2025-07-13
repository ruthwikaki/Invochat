

// This page is obsolete and will be removed.
// Sales data should now be synced from an e-commerce platform integration.

import { AppPage, AppPageHeader } from "@/components/ui/page";
import { Card, CardContent } from "@/components/ui/card";
import Link from 'next/link';
import { Button } from "@/components/ui/button";

export default function QuickSalePage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Quick Sale"
        description="This feature has been removed."
      />
      <Card className="text-center p-8 border-2 border-dashed rounded-lg">
        <CardContent>
            <p className="text-muted-foreground mb-4">
                Sales should now be synced from your e-commerce platform via the Integrations page.
            </p>
             <Button asChild>
                <Link href="/settings/integrations">Connect a Store</Link>
            </Button>
        </CardContent>
      </Card>
    </AppPage>
  )
}
