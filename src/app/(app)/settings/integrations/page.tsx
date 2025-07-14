
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { IntegrationsClientPage } from "@/features/integrations/components/IntegrationsPage";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";

function IntegrationsLoadingSkeleton() {
    return (
        <div className="space-y-6">
            <Skeleton className="h-32 w-full" />
            <Skeleton className="h-32 w-full" />
        </div>
    )
}

export default function IntegrationsPage() {
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Integrations"
                description="Connect your e-commerce platforms and other services to sync data automatically."
            />
            <Suspense fallback={<IntegrationsLoadingSkeleton />}>
                <IntegrationsClientPage />
            </Suspense>
        </div>
    )
}
