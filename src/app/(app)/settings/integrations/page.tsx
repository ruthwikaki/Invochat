
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { IntegrationsClientPage } from "@/features/integrations/components/IntegrationsPage";
import { Suspense } from "react";
import { Skeleton } from "@/components/ui/skeleton";
import { Card, CardContent } from "@/components/ui/card";
import { QueryClient, HydrationBoundary, dehydrate } from '@tanstack/react-query';
import { getIntegrations } from "@/app/data-actions";

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

export default async function IntegrationsPage() {
    const queryClient = new QueryClient();
    await queryClient.prefetchQuery({
        queryKey: ['integrations'],
        queryFn: getIntegrations,
    });

    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Integrations"
                description="Connect your e-commerce platforms and other services to sync data automatically."
            />
            <HydrationBoundary state={dehydrate(queryClient)}>
                <Suspense fallback={<IntegrationsLoadingSkeleton />}>
                    <IntegrationsClientPage />
                </Suspense>
            </HydrationBoundary>
        </div>
    )
}
