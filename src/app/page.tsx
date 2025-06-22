import { AppSidebar } from '@/components/app-sidebar';
import { ChatInterface } from '@/components/chat/chat-interface';
import { Dashboard } from '@/components/dashboard';
import { SidebarProvider } from '@/components/ui/sidebar';

export default function Home() {
  return (
    <SidebarProvider>
      <div className="flex h-dvh w-full bg-background">
        <AppSidebar />
        <main className="flex flex-1 flex-col overflow-y-auto">
          <Dashboard />
          <ChatInterface />
        </main>
      </div>
    </SidebarProvider>
  );
}
