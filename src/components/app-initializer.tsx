
'use client';

import type { ReactNode } from "react";
import { useAuth } from "@/context/auth-context";
import { Skeleton } from "./ui/skeleton";
import ErrorBoundary from "./error-boundary";
import type { z } from "zod";
import type { envValidation } from "@/config/app-config";
import { MissingEnvVarsPage } from "./missing-env-vars-page";


type ValidationResult = z.SafeParseReturnType<z.input<typeof envValidation._def.schema>, z.output<typeof envValidation._def.schema>>;

interface AppInitializerProps {
    children: ReactNode;
    validationResult: ValidationResult;
}

// This component now acts as a gatekeeper, showing a loading state until
// the authentication status is resolved. This prevents flashes of unauthenticated content.
export function AppInitializer({ children, validationResult }: AppInitializerProps) {
    const { loading } = useAuth();

    // First, check for valid environment variables. This is a hard requirement.
    if (!validationResult.success) {
        const errorDetails = validationResult.error.flatten().fieldErrors;
        return <MissingEnvVarsPage errors={errorDetails} />;
    }

    // Then, show a loading skeleton while the user's session is being verified.
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
    
    // Once everything is ready, render the application within an error boundary.
    return (
        <ErrorBoundary onReset={() => window.location.reload()}>
            {children}
        </ErrorBoundary>
    );
}
