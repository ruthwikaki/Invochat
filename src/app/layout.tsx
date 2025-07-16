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

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-sans',
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
        <body className={cn('font-sans antialiased', inter.variable)}>
          <MissingEnvVarsPage errors={errorDetails} />
        </body>
      </html>
    );
  }

  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn('font-sans antialiased', inter.variable)}>
        <ThemeProvider
            attribute="class"
            defaultTheme="system"
            enableSystem
            disableTransitionOnChange
        >
          <QueryClientProvider>
            <AuthProvider>
                <AppInitializer>
                  {children}
                </AppInitializer>
                <Toaster />
            </AuthProvider>
          </QueryClientProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
