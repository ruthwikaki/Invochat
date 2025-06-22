import { AppSidebar } from '@/components/app-sidebar';
import { ChatWidget } from '@/components/chat/chat-widget';
import { SidebarProvider } from '@/components/ui/sidebar';

export default function AppLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
          {children}
        </main>
        <ChatWidget />
      </div>
    </SidebarProvider>
  );
}
