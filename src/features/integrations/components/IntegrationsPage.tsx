
'use client';

import { useState } from 'react';
import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { ShopifyConnectModal } from './ShopifyConnectModal';
import { useIntegrations } from '../hooks/useIntegrations';
import { IntegrationCard } from './IntegrationCard';
import { Skeleton } from '@/components/ui/skeleton';
import { motion } from 'framer-motion';

function ShopifyConnectCard({ onConnectClick }: { onConnectClick: () => void }) {
    return (
        <Card className="bg-background/50 backdrop-blur-sm border-[#95BF47]/30">
            <div className="p-6 flex flex-col md:flex-row items-center gap-6">
                <motion.div 
                    whileHover={{ scale: 1.05 }}
                    className="bg-contain bg-center bg-no-repeat h-16 w-16"
                    style={{ backgroundImage: `url('https://cdn.shopify.com/shopify-marketing_assets/static/shopify-favicon.png')`}}
                />
                <div className="flex-1 text-center md:text-left">
                    <h3 className="text-lg font-semibold">Shopify</h3>
                    <p className="text-sm text-muted-foreground">
                        Sync your products, inventory levels, and orders directly from your Shopify store.
                    </p>
                </div>
                <Button onClick={onConnectClick} className="bg-[#95BF47] hover:bg-[#84ac3d] text-white">
                    Connect Store
                </Button>
            </div>
        </Card>
    );
}


export function IntegrationsClientPage() {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const { integrations, loading, error, triggerSync, disconnect } = useIntegrations();

    const shopifyIntegration = integrations.find(i => i.platform === 'shopify');
    
    if (loading) {
        return <Skeleton className="h-48 w-full" />
    }

    if (error) {
        return <p className="text-destructive">{error}</p>
    }

    return (
        <div className="space-y-6">
            <ShopifyConnectModal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
            />
            
            {shopifyIntegration ? (
                <IntegrationCard
                    integration={shopifyIntegration}
                    onSync={triggerSync}
                    onDisconnect={disconnect}
                />
            ) : (
                 <ShopifyConnectCard onConnectClick={() => setIsModalOpen(true)} />
            )}
        </div>
    );
}
