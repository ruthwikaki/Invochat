

'use client';

import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import type { Integration, Platform } from '@/types';
import { formatDistanceToNow } from 'date-fns';
import { Loader2, CheckCircle, AlertTriangle, RefreshCw, TestTube2 } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog';
import { PlatformLogo } from './platform-logos';
import { useState, useEffect } from 'react';
import { Badge } from '@/components/ui/badge';

interface IntegrationCardProps {
    integration: Integration;
    onSync: (id: string, platform: Platform) => void;
    onDisconnect: (id: string) => void;
}

export function IntegrationCard({ integration, onSync, onDisconnect }: IntegrationCardProps) {
    const isSyncing = integration.sync_status?.startsWith('syncing');
    const [formattedDate, setFormattedDate] = useState('');

    useEffect(() => {
        if (integration.last_sync_at) {
            setFormattedDate(formatDistanceToNow(new Date(integration.last_sync_at), { addSuffix: true }));
        }
    }, [integration.last_sync_at]);
    
    const isDemo = integration.platform === 'amazon_fba';

    const renderStatus = () => {
        switch (integration.sync_status) {
            case 'syncing':
                return <span className="flex items-center gap-2 text-sm text-blue-500"><Loader2 className="h-4 w-4 animate-spin" /> Starting sync...</span>;
            case 'syncing_products':
                return <span className="flex items-center gap-2 text-sm text-blue-500"><Loader2 className="h-4 w-4 animate-spin" /> Syncing products...</span>;
            case 'syncing_orders':
                return <span className="flex items-center gap-2 text-sm text-blue-500"><Loader2 className="h-4 w-4 animate-spin" /> Syncing orders...</span>;
            case 'success':
                return <span className="flex items-center gap-2 text-sm text-success"><CheckCircle className="h-4 w-4" /> Last synced {formattedDate || 'never'}</span>;
            case 'failed':
                return <span className="flex items-center gap-2 text-sm text-destructive"><AlertTriangle className="h-4 w-4" /> Sync failed</span>;
            default:
                return <span className="text-sm text-muted-foreground">Ready to sync.</span>;
        }
    };

    const getBrandColor = () => {
        switch(integration.platform) {
            case 'shopify': return 'border-green-500/20';
            case 'woocommerce': return 'border-purple-500/20';
            case 'amazon_fba': return 'border-orange-500/20';
            default: return 'border-border';
        }
    }

    return (
        <Card className={`bg-gradient-to-br from-card to-muted/50 shadow-lg ${getBrandColor()}`}>
            <div className="p-6 flex flex-col md:flex-row items-center gap-6">
                 <PlatformLogo platform={integration.platform} className="h-16 w-16" />
                <div className="flex-1 text-center md:text-left">
                    <div className="flex items-center gap-2 justify-center md:justify-start">
                        <h3 className="text-lg font-semibold">{integration.shop_name}</h3>
                        {isDemo && <Badge variant="outline" className="border-amber-500/50 bg-amber-500/10 text-amber-600"><TestTube2 className="h-3 w-3 mr-1" />Demo Mode</Badge>}
                    </div>
                    <p className="text-sm text-muted-foreground">{integration.shop_domain?.replace('https://', '') || 'Integration'}</p>
                    {renderStatus()}
                </div>
                <div className="flex items-center gap-2">
                    <Button variant="outline" onClick={() => onSync(integration.id, integration.platform)} disabled={isSyncing}>
                        <RefreshCw className={`mr-2 h-4 w-4 ${isSyncing ? 'animate-spin' : ''}`} />
                        Sync Now
                    </Button>
                     <AlertDialog>
                        <AlertDialogTrigger asChild>
                            <Button variant="destructive">Disconnect</Button>
                        </AlertDialogTrigger>
                        <AlertDialogContent>
                            <AlertDialogHeader>
                                <AlertDialogTitle>Are you sure?</AlertDialogTitle>
                                <AlertDialogDescription>
                                    Disconnecting your store will stop all future data syncs. Your existing synced data will not be deleted.
                                </AlertDialogDescription>
                            </AlertDialogHeader>
                            <AlertDialogFooter>
                                <AlertDialogCancel>Cancel</AlertDialogCancel>
                                <AlertDialogAction onClick={() => onDisconnect(integration.id)} className="bg-destructive hover:bg-destructive/90">
                                    Yes, Disconnect
                                </AlertDialogAction>
                            </AlertDialogFooter>
                        </AlertDialogContent>
                    </AlertDialog>
                </div>
            </div>
             {isDemo && (
                <div className="border-t bg-amber-500/5 px-6 py-2 text-xs text-amber-700 dark:text-amber-400">
                    <strong>Demo Mode:</strong> This integration uses sample data and does not connect to a real Amazon account. Syncing will import pre-defined mock products and sales.
                </div>
            )}
        </Card>
    );
}
    