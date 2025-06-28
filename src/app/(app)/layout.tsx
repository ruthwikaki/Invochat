
'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { SidebarProvider } from '@/components/ui/sidebar';
import { AnimatePresence, motion } from 'framer-motion';
import { usePathname } from 'next/navigation';
import ErrorBoundary from '@/components/error-boundary';
import { useState, useCallback } from 'react';
import { DynamicThemeProvider } from '@/components/dynamic-theme-provider';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  const [resetKey, setResetKey] = useState(0);

  const handleReset = useCallback(() => {
    setResetKey((prevKey) => prevKey + 1);
  }, []);

  return (
    <SidebarProvider>
      <DynamicThemeProvider />
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
          <ErrorBoundary key={resetKey} onReset={handleReset}>
            <AnimatePresence mode="wait">
              <motion.div
                key={pathname}
                initial={{ opacity: 0, y: 15 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: 15 }}
                transition={{
                  y: { type: 'spring', stiffness: 300, damping: 30 },
                  opacity: { duration: 0.2 },
                }}
                className="h-full"
              >
                {children}
              </motion.div>
            </AnimatePresence>
          </ErrorBoundary>
        </main>
      </div>
    </SidebarProvider>
  );
}
