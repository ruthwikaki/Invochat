
'use client';

import type { ReactNode } from "react";
import { useAuth } from "@/context/auth-context";
import { Skeleton } from "./ui/skeleton";
import ErrorBoundary from "./error-boundary";
import { MissingEnvVarsPage } from "./missing-env-vars-page";
import type { z } from "zod";


type ValidationResult = z.SafeParseReturnType<any, any>;


interface AppInitializerProps {
    children: ReactNode;
    validationResult: ValidationResult;
}

export function AppInitializer({ children, validationResult }: AppInitializerProps) {
    const { loading } = useAuth();

    // In development, only show env error page for critical missing vars
    if (!validationResult.success) {
        const errorDetails = validationResult.error.flatten().fieldErrors;
        const criticalErrors = {
            NEXT_PUBLIC_SUPABASE_URL: errorDetails.NEXT_PUBLIC_SUPABASE_URL,
            NEXT_PUBLIC_SUPABASE_ANON_KEY: errorDetails.NEXT_PUBLIC_SUPABASE_ANON_KEY,
            SUPABASE_SERVICE_ROLE_KEY: errorDetails.SUPABASE_SERVICE_ROLE_KEY,
        };
        
        // Only show error page if critical vars are missing
        const hasCriticalErrors = Object.values(criticalErrors).some(error => error !== undefined);
        
        if (hasCriticalErrors) {
            return <MissingEnvVarsPage errors={criticalErrors} />;
        }
        
        // Log warnings for non-critical vars in development
        if (process.env.NODE_ENV === 'development') {
            console.warn('Non-critical environment variables missing:', errorDetails);
        }
    }

    if (loading) {
        return (
            <div className="flex h-screen w-screen items-center justify-center">
                <div className="flex flex-col items-center gap-4">
                    <Skeleton className="h-16 w-16 rounded-full" />
                    <Skeleton className="h-8 w-48" />
                </div>
            </div>
        )
    }
    
    return (
        <ErrorBoundary onReset={() => window.location.reload()}>
            {children}
        </ErrorBoundary>
    );
}
