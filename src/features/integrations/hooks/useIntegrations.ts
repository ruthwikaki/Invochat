
'use client';

import { getIntegrations } from '@/app/data-actions';
import type { Integration } from '@/types';
import { useAuth } from '@/context/auth-context';
import { useQuery } from '@tanstack/react-query';

export function useIntegrations() {
    const { user } = useAuth();

    const { data: integrations, isLoading, error } = useQuery<Integration[], Error>({
        queryKey: ['integrations'],
        queryFn: getIntegrations,
        enabled: !!user, // Only fetch if the user is logged in
    });

    return { 
        integrations: integrations || [], 
        loading: isLoading, 
        error: error ? error.message : null, 
    };
}
