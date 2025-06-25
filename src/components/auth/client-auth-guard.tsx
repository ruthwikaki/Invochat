'use client';

import { useEffect, useState } from 'react';
import { useRouter, usePathname } from 'next/navigation';
import { createBrowserSupabaseClient } from '@/lib/supabase/client';

const PUBLIC_PATHS = ['/login', '/signup', '/quick-test'];

export function ClientAuthGuard({ children }: { children: React.ReactNode }) {
  const [isChecking, setIsChecking] = useState(true);
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    const checkAuth = async () => {
      try {
        const supabase = createBrowserSupabaseClient();
        const { data: { session } } = await supabase.auth.getSession();
        
        const isPublicPath = PUBLIC_PATHS.some(path => pathname.startsWith(path));
        
        if (!session && !isPublicPath) {
          router.replace('/login');
        }
      } catch (error) {
        console.error('Auth check error:', error);
        // On error, redirect to login for safety
        const isPublicPath = PUBLIC_PATHS.some(path => pathname.startsWith(path));
        if (!isPublicPath) {
          router.replace('/login');
        }
      } finally {
        // Always set isChecking to false when done
        setIsChecking(false);
      }
    };

    checkAuth();
  }, [pathname, router]);

  // Show loading spinner while checking auth
  if (isChecking) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-background">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  return <>{children}</>;
}
