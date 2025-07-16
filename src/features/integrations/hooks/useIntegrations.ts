
'use client';

import { useState, useTransition } from 'react';
import { getIntegrations } from '@/app/data-actions';
import type { Integration, Platform } from '@/types';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import { getErrorMessage } from '@/lib/error-handler';
import { useQuery, useQueryClient } from '@tanstack/react-query';

export function useIntegrations() {
    const { user } = useAuth();
    const { toast } = useToast();
    const queryClient = useQueryClient();
    const [isSyncing, startSyncTransition] = useTransition();

    const { data: integrations, isLoading, error } = useQuery<Integration[], Error>({
        queryKey: ['integrations'],
        queryFn: getIntegrations,
        enabled: !!user, // Only fetch if the user is logged in
    });
    
    const triggerSync = (integrationId: string, platform: Platform) => {
        startSyncTransition(async () => {
            // Optimistically update the UI
            queryClient.setQueryData<Integration[]>(['integrations'], (oldData) => 
                oldData ? oldData.map(i => i.id === integrationId ? { ...i, sync_status: 'syncing' } : i) : []
            );

            try {
                const payload = { integrationId };
                const apiUrl = `/api/${platform}/sync`;

                const response = await fetch(apiUrl, {
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
                
            } catch(e) {
                toast({ variant: 'destructive', title: 'Sync Failed', description: getErrorMessage(e) });
                // On failure, invalidate the query to refetch and revert the optimistic update
                queryClient.invalidateQueries({ queryKey: ['integrations'] });
            }
        });
    };

    return { 
        integrations: integrations || [], 
        loading: isLoading, 
        error: error ? error.message : null, 
        triggerSync,
        isSyncing
    };
}
