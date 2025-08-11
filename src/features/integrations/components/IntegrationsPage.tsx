
'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardDescription, CardHeader, CardTitle, CardFooter, CardContent } from '@/components/ui/card';
import { ShopifyConnectModal } from './ShopifyConnectModal';
import { WooCommerceConnectModal } from './WooCommerceConnectModal';
import { AmazonConnectModal } from './AmazonConnectModal';
import { useIntegrations } from '../hooks/useIntegrations';
import { IntegrationCard } from './IntegrationCard';
import { Skeleton } from '@/components/ui/skeleton';
import { motion } from 'framer-motion';
import { PlatformLogo } from './platform-logos';
import type { Platform, Integration } from '@/types';
import { disconnectIntegration, reconcileInventory } from '@/app/data-actions';
import { useToast } from '@/hooks/use-toast';
import { Loader2, AlertCircle } from 'lucide-react';
import { Alert, AlertTitle, AlertDescription } from '@/components/ui/alert';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { getErrorMessage } from '@/lib/error-handler';
import { useRouter } from 'next/navigation';

function PlatformConnectCard({
    platform,
    description,
    onConnectClick,
    comingSoon = false,
}: {
    platform: Platform;
    description: string;
    onConnectClick: () => void;
    comingSoon?: boolean;
}) {
    return (
        <Card className="bg-background/50 backdrop-blur-sm">
            <div className="p-6 flex flex-col md:flex-row items-center gap-6">
                <motion.div whileHover={{ scale: 1.05 }}>
                    <PlatformLogo platform={platform} className="h-16 w-16" />
                </motion.div>
                <div className="flex-1 text-center md:text-left">
                    <h3 className="text-lg font-semibold capitalize">{platform.replace(/_/g, ' ')}</h3>
                    <p className="text-sm text-muted-foreground">{description}</p>
                </div>
                <Button onClick={onConnectClick} disabled={comingSoon}>
                    {comingSoon ? 'Coming Soon' : 'Connect Store'}
                </Button>
            </div>
        </Card>
    );
}

function ReconciliationCard({ integrationId }: { integrationId: string | undefined }) {
    const { toast } = useToast();
    const router = useRouter();
    const [isReconciling, startReconciliation] = useState(false);

    if (!integrationId) return null;

    const handleReconcile = async () => {
        startReconciliation(true);
        const result = await reconcileInventory(integrationId);
        if (result.success) {
            toast({
                title: 'Reconciliation Started',
                description: 'Inventory levels are being updated. The page will now refresh.',
            });
            router.refresh();
        } else {
            toast({
                title: 'Reconciliation Failed',
                description: result.error,
                variant: 'destructive',
            });
        }
        startReconciliation(false);
    };

    return (
        <Card>
            <CardHeader>
                <CardTitle>Inventory Reconciliation</CardTitle>
                <CardDescription>
                    Manually sync your inventory quantities from your e-commerce platform to ARVO. This is useful if you suspect a discrepancy.
                </CardDescription>
            </CardHeader>
            <CardContent>
                <Alert>
                    <AlertCircle className="h-4 w-4" />
                    <AlertTitle>How it works</AlertTitle>
                    <AlertDescription>
                        This process will fetch the current stock levels from your store and create an inventory adjustment in ARVO to match the platform's quantity.
                    </AlertDescription>
                </Alert>
            </CardContent>
            <CardFooter>
                <Button onClick={handleReconcile} disabled={isReconciling}>
                    {isReconciling && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                    Reconcile Inventory
                </Button>
            </CardFooter>
        </Card>
    );
}


export function IntegrationsClientPage() {
    const [isShopifyModalOpen, setIsShopifyModalOpen] = useState(false);
    const [isWooCommerceModalOpen, setIsWooCommerceModalOpen] = useState(false);
    const [isAmazonModalOpen, setIsAmazonModalOpen] = useState(false);
    const { toast } = useToast();
    const queryClient = useQueryClient();
    const router = useRouter();

    const { integrations, loading, error } = useIntegrations();
    
    const syncMutation = useMutation({
        mutationFn: async ({ integrationId, platform }: { integrationId: string, platform: Platform }) => {
            const response = await fetch(`/api/${platform}/sync`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ integrationId }),
            });
            if (!response.ok) {
                const errorResult = await response.json();
                throw new Error(errorResult.error || `Sync failed with status ${response.status}`);
            }
            return response.json();
        },
        onMutate: async ({ integrationId }) => {
            // Optimistically update the UI to show a syncing state
            await queryClient.cancelQueries({ queryKey: ['integrations'] });
            const previousIntegrations = queryClient.getQueryData<Integration[]>(['integrations']);
            queryClient.setQueryData<Integration[]>(['integrations'], old =>
                old?.map(i => i.id === integrationId ? { ...i, sync_status: 'syncing' } : i)
            );
            toast({ title: 'Sync Started', description: 'Your data will be updated shortly.'});
            return { previousIntegrations };
        },
        onSuccess: () => {
            toast({
                title: 'Sync Complete!',
                description: 'Your data has been updated. The page will now refresh.',
            });
            // After a successful sync, refresh server components to show new data
            router.refresh();
        },
        onError: (err, _variables, context) => {
            // Rollback on error
            if (context?.previousIntegrations) {
                queryClient.setQueryData(['integrations'], context.previousIntegrations);
            }
            toast({ variant: 'destructive', title: 'Sync Failed', description: getErrorMessage(err) });
        },
        onSettled: () => {
            // Refetch integrations to get the final status from the server
             void queryClient.invalidateQueries({ queryKey: ['integrations'] });
        },
    });

    const disconnectMutation = useMutation({
      mutationFn: disconnectIntegration,
      onSuccess: (result) => {
        if(result.success) {
          toast({ title: 'Integration Disconnected' });
          void queryClient.invalidateQueries({ queryKey: ['integrations'] });
        } else {
          toast({ variant: 'destructive', title: 'Error', description: result.error });
        }
      },
      onError: (err) => {
        toast({ variant: 'destructive', title: 'Error', description: getErrorMessage(err) });
      }
    });

    const connectedPlatforms = new Set(integrations.map(i => i.platform));
    
    if (loading) {
        return (
            <div className="space-y-6">
                <Skeleton className="h-32 w-full" />
                <Skeleton className="h-32 w-full" />
            </div>
        )
    }

    if (error) {
        return <p className="text-destructive">{error}</p>
    }

    return (
        <div className="space-y-8">
            <ShopifyConnectModal
                isOpen={isShopifyModalOpen}
                onClose={() => { setIsShopifyModalOpen(false); }}
            />
             <WooCommerceConnectModal
                isOpen={isWooCommerceModalOpen}
                onClose={() => { setIsWooCommerceModalOpen(false); }}
            />
            <AmazonConnectModal
                isOpen={isAmazonModalOpen}
                onClose={() => { setIsAmazonModalOpen(false); }}
            />
            
            <section data-testid="integrations-connected">
                <h2 className="text-xl font-semibold mb-4">Connected Integrations</h2>
                <div className="space-y-4">
                    {integrations.length > 0 ? (
                        integrations.map(integration => (
                             <IntegrationCard
                                key={integration.id}
                                integration={integration}
                                onSync={() => { syncMutation.mutate({ integrationId: integration.id, platform: integration.platform }); }}
                                onDisconnect={(formData) => { disconnectMutation.mutate(formData); }}
                            />
                        ))
                    ) : (
                        <Card className="text-center p-8 border-dashed">
                           <CardTitle>No Integrations Connected</CardTitle>
                           <CardDescription className="mt-2">Connect an app below to get started.</CardDescription>
                        </Card>
                    )}
                </div>
            </section>

             {integrations.length > 0 && (
                <div>
                     <h2 className="text-xl font-semibold my-4">Advanced Tools</h2>
                    <ReconciliationCard integrationId={integrations[0]?.id} />
                </div>
            )}
            
            <section data-testid="integrations-available">
                <h2 className="text-xl font-semibold mb-4">Available Integrations</h2>
                <div className="space-y-4">
                    {!connectedPlatforms.has('shopify') && (
                         <PlatformConnectCard 
                            platform="shopify"
                            description="Sync your products, inventory levels, and orders directly from your Shopify store."
                            onConnectClick={() => { setIsShopifyModalOpen(true); }}
                         />
                    )}
                    {!connectedPlatforms.has('woocommerce') && (
                         <PlatformConnectCard 
                            platform="woocommerce"
                            description="Sync your products, inventory, and orders from your WooCommerce-powered site."
                            onConnectClick={() => { setIsWooCommerceModalOpen(true); }}
                         />
                    )}
                     {!connectedPlatforms.has('amazon_fba') && (
                         <PlatformConnectCard 
                            platform="amazon_fba"
                            description="Connect your Amazon Seller Central account to manage FBA inventory."
                            onConnectClick={() => { setIsAmazonModalOpen(true); }}
                         />
                    )}
                </div>
            </section>
        </div>
    );
}
