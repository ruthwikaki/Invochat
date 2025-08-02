import type { Metadata } from 'next';
import { Inter } from 'next/font/google';
import './globals.css';
import { cn } from '@/lib/utils';
import { Toaster } from "@/components/ui/toaster";
import { ThemeProvider } from '@/components/theme-provider';
import { AuthProvider } from '@/context/auth-context';
import { AppInitializer } from '@/components/app-initializer';
import { envValidation } from '@/config/app-config';

const inter = Inter({
  subsets: ['latin'],
  variable: '--font-sans',
});

export const metadata: Metadata = {
  title: 'AIventory - Conversational Inventory Intelligence',
  description: 'AI-powered inventory management for AIventory',
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  console.log('🏗️ RootLayout rendering');
  console.log('🔧 Env validation success:', envValidation.success);
  
  if (!envValidation.success) {
    console.error('❌ Env validation failed:', envValidation.error.flatten());
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
          <AuthProvider>
            <AppInitializer validationResult={envValidation}>
              {children}
            </AppInitializer>
            <Toaster />
          </AuthProvider>
        </ThemeProvider>
      </body>
    </html>
  );
}
