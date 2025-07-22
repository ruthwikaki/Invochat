
'use client';

import type { ReactNode } from "react";
import { useAuth } from "@/context/auth-context";
import { Skeleton } from "./ui/skeleton";

// This component now acts as a gatekeeper, showing a loading state until
// the authentication status is resolved. This prevents flashes of unauthenticated content.
export function AppInitializer({ children }: { children: ReactNode }) {
    const { loading } = useAuth();

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
    
    return <>{children}</>;
}
