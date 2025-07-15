
import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { cn } from '@/lib/utils';
import { Toaster } from "@/components/ui/toaster";
import { ThemeProvider } from '@/components/theme-provider';
import { AppInitializer } from '@/components/app-initializer';
import { envValidation } from '@/config/app-config';
import { MissingEnvVarsPage } from '@/components/missing-env-vars-page';
import { AuthProvider } from '@/context/auth-context';
import { QueryClientProvider } from '@/context/query-client-provider';
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';
import { Sidebar, SidebarProvider } from '@/components/ui/sidebar';
import { AppSidebar } from '@/components/nav/sidebar';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-body',
});

export const metadata: Metadata = {
  title: 'ARVO - Conversational Inventory Intelligence',
  description: 'AI-powered inventory management for ARVO',
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  if (!envValidation.success) {
    const errorDetails = envValidation.error.flatten().fieldErrors;
    return (
      <html lang="en">
        <body className={cn('font-body antialiased', inter.variable)}>
          <MissingEnvVarsPage errors={errorDetails} />
        </body>
      </html>
    );
  }

  const cookieStore = cookies();
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        get(name: string) {
          return cookieStore.get(name)?.value
        },
      },
    }
  );

  const { data: { session } } = await supabase.auth.getSession();

  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn('font-body antialiased', inter.variable)}>
        <ThemeProvider
            attribute="class"
            defaultTheme="system"
            enableSystem
            disableTransitionOnChange
        >
          <QueryClientProvider>
            <AuthProvider>
                <AppInitializer>
                  {session ? (
                    <SidebarProvider>
                      <div className="relative flex h-dvh w-full bg-background">
                        <div className="absolute inset-0 -z-10 h-full w-full bg-background bg-[radial-gradient(theme(colors.border)_1px,transparent_1px)] [background-size:32px_32px]"></div>
                        <Sidebar>
                          <AppSidebar />
                        </Sidebar>
                        <main className="flex flex-1 flex-col overflow-y-auto">
                          <div className="flex-1 p-4 md:p-6 lg:p-8">
                            {children}
                          </div>
                        </main>
                      </div>
                    </SidebarProvider>
                  ) : (
                    <>{children}</>
                  )}
                </AppInitializer>
                <Toaster />
            </AuthProvider>
          </QueryClientProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
