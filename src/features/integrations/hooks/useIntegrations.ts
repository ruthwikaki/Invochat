
'use client';

import { useState, useEffect, useTransition } from 'react';
import { getIntegrations, disconnectIntegration as disconnectAction } from '@/app/data-actions';
import { Integration } from '../types';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';

export function useIntegrations() {
    const { user } = useAuth();
    const { toast } = useToast();
    const [integrations, setIntegrations] = useState<Integration[]>([]);
    const [loading, setLoading] = useState(true);
    const [error, setError] = useState<string | null>(null);
    const [isSyncing, startSyncTransition] = useTransition();
    
    useEffect(() => {
        if (!user) { // Don't fetch if no user
            setLoading(false);
            return;
        }
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
    }, [user]);
    
    const triggerSync = (integrationId: string) => {
        startSyncTransition(async () => {
            try {
                const payload = { integrationId };

                const response = await fetch('/api/shopify/sync', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify(payload),
                });

                if (!response.ok) {
                    const errorText = await response.text();
                    try {
                        const errorJson = JSON.parse(errorText);
                        throw new Error(errorJson.error || 'An unknown error occurred during sync.');
                    } catch (e) {
                        throw new Error(errorText || 'An unknown server error occurred.');
                    }
                }
                
                const result = await response.json();
                toast({ title: 'Sync Started', description: result.message || 'Your data will be updated shortly.'});
                setIntegrations(prev => 
                    prev.map(i => i.id === integrationId ? { ...i, sync_status: 'syncing' } : i)
                );
            } catch(e) {
                toast({ variant: 'destructive', title: 'Sync Failed', description: getErrorMessage(e) });
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
