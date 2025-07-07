
import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { cn } from '@/lib/utils';
import { Toaster } from "@/components/ui/toaster"
import { ThemeProvider } from '@/components/theme-provider';
import { AppInitializer } from '@/components/app-initializer';
import { envValidation } from '@/config/app-config';
import { MissingEnvVarsPage } from '@/components/missing-env-vars-page';
import { AuthProvider } from '@/context/auth-context';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-body',
});

export const metadata: Metadata = {
  title: 'InvoChat - Conversational Inventory Intelligence',
  description: 'AI-powered inventory management for InvoChat',
};

export default async function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  // This server-side check prevents the app from crashing and instead shows a helpful error page.
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

  return (
    <html lang="en" suppressHydrationWarning>
      <body className={cn('font-body antialiased', inter.variable)}>
        <ThemeProvider
            attribute="class"
            defaultTheme="dark"
            enableSystem={false}
            disableTransitionOnChange
        >
            <AuthProvider>
                <AppInitializer>
                    {children}
                </AppInitializer>
                <Toaster />
            </AuthProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
