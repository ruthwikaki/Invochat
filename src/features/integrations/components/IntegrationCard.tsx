
'use client';

import { Button } from '@/components/ui/button';
import { Card } from '@/components/ui/card';
import { Integration } from '../types';
import { formatDistanceToNow } from 'date-fns';
import { Loader2, CheckCircle, AlertTriangle, RefreshCw } from 'lucide-react';
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog';
import { PlatformLogo } from './platform-logos';

interface IntegrationCardProps {
    integration: Integration;
    onSync: (id: string) => void;
    onDisconnect: (id: string) => void;
}

export function IntegrationCard({ integration, onSync, onDisconnect }: IntegrationCardProps) {
    const isSyncing = integration.sync_status === 'syncing';
    
    const renderStatus = () => {
        switch (integration.sync_status) {
            case 'syncing':
                return <span className="flex items-center gap-2 text-sm text-blue-500"><Loader2 className="h-4 w-4 animate-spin" /> Syncing now...</span>;
            case 'success':
                return <span className="flex items-center gap-2 text-sm text-success"><CheckCircle className="h-4 w-4" /> Last synced {formatDistanceToNow(new Date(integration.last_sync_at!), { addSuffix: true })}</span>;
            case 'failed':
                return <span className="flex items-center gap-2 text-sm text-destructive"><AlertTriangle className="h-4 w-4" /> Sync failed</span>;
            default:
                return <span className="text-sm text-muted-foreground">Ready to sync.</span>;
        }
    };

    return (
        <Card className="bg-gradient-to-br from-card to-muted/50 border-green-500/20 shadow-lg">
            <div className="p-6 flex flex-col md:flex-row items-center gap-6">
                 <PlatformLogo platform={integration.platform} className="h-16 w-16" />
                <div className="flex-1 text-center md:text-left">
                    <h3 className="text-lg font-semibold">{integration.shop_name}</h3>
                    <p className="text-sm text-muted-foreground">{integration.shop_domain?.replace('https://', '')}</p>
                    {renderStatus()}
                </div>
                <div className="flex items-center gap-2">
                    <Button variant="outline" onClick={() => onSync(integration.id)} disabled={isSyncing}>
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
        </Card>
    );
}
