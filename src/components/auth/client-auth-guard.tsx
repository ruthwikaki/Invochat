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
      const supabase = createBrowserSupabaseClient();
      const { data: { session } } = await supabase.auth.getSession();
      
      const isPublicPath = PUBLIC_PATHS.some(path => pathname.startsWith(path));
      
      if (!session && !isPublicPath) {
        router.replace('/login');
      } else {
        setIsChecking(false);
      }
    };

    checkAuth();
  }, [pathname, router]);

  if (isChecking) {
    return (
      <div className="flex h-screen w-full items-center justify-center">
        <div className="animate-spin rounded-full h-8 w-8 border-b-2 border-primary"></div>
      </div>
    );
  }

  return <>{children}</>;
}
