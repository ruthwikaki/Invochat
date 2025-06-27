
'use client';
import { AppSidebar } from '@/components/app-sidebar';
import { ChatWidget } from '@/components/chat/chat-widget';
import { SidebarProvider } from '@/components/ui/sidebar';
import { AnimatePresence, motion } from 'framer-motion';
import { usePathname } from 'next/navigation';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  const pathname = usePathname();
  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
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
            >
              {children}
            </motion.div>
          </AnimatePresence>
        </main>
        <ChatWidget />
      </div>
    </SidebarProvider>
  );
}
