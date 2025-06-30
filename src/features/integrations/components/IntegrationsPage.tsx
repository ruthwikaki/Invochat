
'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { ShopifyConnectModal } from './ShopifyConnectModal';
import { useIntegrations } from '../hooks/useIntegrations';
import { IntegrationCard } from './IntegrationCard';
import { Skeleton } from '@/components/ui/skeleton';
import { motion } from 'framer-motion';
import { PlatformLogo } from './platform-logos';
import type { Platform } from '../types';

function PlatformConnectCard({
    platform,
    description,
    onConnectClick,
    comingSoon = false,
    brandColor,
}: {
    platform: Platform;
    description: string;
    onConnectClick: () => void;
    comingSoon?: boolean;
    brandColor?: string;
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
                <Button onClick={onConnectClick} disabled={comingSoon} style={brandColor ? { backgroundColor: brandColor, color: 'white' } : {}}>
                    {comingSoon ? 'Coming Soon' : 'Connect Store'}
                </Button>
            </div>
        </Card>
    );
}


export function IntegrationsClientPage() {
    const [isShopifyModalOpen, setIsShopifyModalOpen] = useState(false);
    const { integrations, loading, error, triggerSync, disconnect } = useIntegrations();

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
                onClose={() => setIsShopifyModalOpen(false)}
            />
            
            <div>
                <h2 className="text-xl font-semibold mb-4">Connected Integrations</h2>
                <div className="space-y-4">
                    {integrations.length > 0 ? (
                        integrations.map(integration => (
                             <IntegrationCard
                                key={integration.id}
                                integration={integration}
                                onSync={triggerSync}
                                onDisconnect={disconnect}
                            />
                        ))
                    ) : (
                        <Card className="text-center p-8 border-dashed">
                           <CardTitle>No Integrations Connected</CardTitle>
                           <CardDescription className="mt-2">Connect an app below to get started.</CardDescription>
                        </Card>
                    )}
                </div>
            </div>
            
            <div>
                <h2 className="text-xl font-semibold mb-4">Available Integrations</h2>
                <div className="space-y-4">
                    {!connectedPlatforms.has('shopify') && (
                         <PlatformConnectCard 
                            platform="shopify"
                            description="Sync your products, inventory levels, and orders directly from your Shopify store."
                            onConnectClick={() => setIsShopifyModalOpen(true)}
                            brandColor="#78AB43"
                         />
                    )}
                    {!connectedPlatforms.has('woocommerce') && (
                         <PlatformConnectCard 
                            platform="woocommerce"
                            description="Sync your products, inventory, and orders from your WooCommerce-powered site."
                            onConnectClick={() => {}}
                            brandColor="#96588A"
                            comingSoon
                         />
                    )}
                     {!connectedPlatforms.has('amazon_fba') && (
                         <PlatformConnectCard 
                            platform="amazon_fba"
                            description="Connect your Amazon Seller Central account to manage FBA inventory."
                            onConnectClick={() => {}}
                            brandColor="#FF9900"
                            comingSoon
                         />
                    )}
                </div>
            </div>
        </div>
    );
}
