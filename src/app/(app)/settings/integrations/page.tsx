
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { IntegrationsClientPage } from "@/features/integrations/components/IntegrationsPage";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";

function IntegrationsLoadingSkeleton() {
    return (
        <div className="space-y-6">
            <Card>
                <CardContent className="p-6">
                    <Skeleton className="h-8 w-1/2 mb-4" />
                    <div className="space-y-4">
                        <Skeleton className="h-24 w-full" />
                    </div>
                </CardContent>
            </Card>
             <Card>
                <CardContent className="p-6">
                    <Skeleton className="h-8 w-1/2 mb-4" />
                    <div className="space-y-4">
                        <Skeleton className="h-24 w-full" />
                        <Skeleton className="h-24 w-full" />
                    </div>
                </CardContent>
            </Card>
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
