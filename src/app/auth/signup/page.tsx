
'use client';

import { useEffect } from 'react';
import { useRouter } from 'next/navigation';
import { InvoChatLogo } from '@/components/invochat-logo';

// This is a redirect component to handle the legacy/incorrect path.
export default function RedirectToSignup() {
    const router = useRouter();

    useEffect(() => {
        router.replace('/signup');
    }, [router]);

    return (
        <div className="flex h-dvh w-full flex-col items-center justify-center bg-muted/40 gap-4">
            <InvoChatLogo className="h-12 w-12" />
            <p className="text-muted-foreground">Redirecting...</p>
        </div>
    );
}
