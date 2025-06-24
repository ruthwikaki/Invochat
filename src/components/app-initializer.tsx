
'use client';

import { useAuth } from "@/context/auth-context";
import { AlertTriangle } from "lucide-react";
import type { ReactNode } from "react";
import { Skeleton } from "./ui/skeleton";

function SupabaseNotConfigured() {
    return (
        <div className="flex min-h-dvh flex-col items-center justify-center bg-background p-8 text-center">
            <div className="mx-auto bg-destructive/10 p-4 rounded-full w-fit mb-4">
                <AlertTriangle className="h-10 w-10 text-destructive" />
            </div>
            <h1 className="text-2xl font-bold text-destructive">Configuration Error</h1>
            <p className="mt-2 max-w-md text-muted-foreground">
                The application cannot connect to the database because the Supabase environment variables are missing.
            </p>
            <div className="mt-6 p-4 rounded-md bg-muted text-left text-sm font-mono max-w-md w-full">
                <p className="font-bold">Please add the following to your `.env` file:</p>
                <p className="mt-2">NEXT_PUBLIC_SUPABASE_URL=...your_url...</p>
                <p>NEXT_PUBLIC_SUPABASE_ANON_KEY=...your_key...</p>
            </div>
        </div>
    );
}

function FullPageLoader() {
    return (
        <div className="flex h-dvh w-full items-center justify-center bg-background p-8">
            <div className="w-full max-w-md space-y-4">
                <Skeleton className="h-10 w-3/4" />
                <Skeleton className="h-8 w-1/2" />
                <Skeleton className="h-12 w-full" />
            </div>
      </div>
    )
}


export function AppInitializer({ children }: { children: ReactNode }) {
    const { isConfigured, loading } = useAuth();

    if (loading) {
        // While checking, we show a loader to prevent flashes of content.
        return <FullPageLoader />;
    }

    if (!isConfigured) {
        return <SupabaseNotConfigured />;
    }

    return <>{children}</>;
}
