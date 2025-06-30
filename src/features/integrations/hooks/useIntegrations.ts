
'use client';

import { useState, useEffect, useTransition } from 'react';
import { getIntegrations, disconnectIntegration as disconnectAction } from '@/app/data-actions';
import { ShopifyIntegration } from '../types';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';

export function useIntegrations() {
    const { user } = useAuth();
    const { toast } = useToast();
    const [integrations, setIntegrations] = useState<ShopifyIntegration[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [isSyncing, startSyncTransition] = useTransition();
    
    useEffect(() => {
        async function fetchIntegrations() {
            try {
                const data = await getIntegrations();
                setIntegrations(data);
            } catch (e: any) {
                setError(e.message);
            } finally {
                setLoading(false);
            }
        }
        fetchIntegrations();
    }, []);
    
    const triggerSync = (integrationId: string) => {
        startSyncTransition(async () => {
            const payload = {
                integrationId,
                companyId: user?.app_metadata?.company_id,
            };

            const response = await fetch('/api/shopify/sync', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify(payload),
            });

            const result = await response.json();
            if (response.ok) {
                toast({ title: 'Sync Started', description: 'Your data will be updated shortly.'});
                // Optimistically update the UI
                setIntegrations(prev => 
                    prev.map(i => i.id === integrationId ? { ...i, sync_status: 'syncing' } : i)
                );
            } else {
                 toast({ variant: 'destructive', title: 'Sync Failed', description: result.error });
            }
        });
    };

    const disconnect = async (integrationId: string) => {
        const result = await disconnectAction(integrationId);
         if (result.success) {
            toast({ title: 'Integration Disconnected' });
            setIntegrations(prev => prev.filter(i => i.id !== integrationId));
        } else {
            toast({ variant: 'destructive', title: 'Error', description: result.error });
        }
    };

    return { integrations, loading, error, triggerSync, disconnect };
}
