
'use client';

import { cn } from '@/lib/utils';
import { SidebarTrigger } from './sidebar';
import type { ReactNode } from 'react';

/**
 * A container for a full page view. Provides consistent padding and max-width.
 */
export function AppPage({ children, className }: { children: ReactNode; className?: string }) {
  return (
    <div className={cn('w-full', className)}>
        {children}
    </div>
  );
}

/**
 * A standard page header with a title, description, and optional action buttons.
 */
export function AppPageHeader({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children?: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-4 md:flex-row md:items-start md:justify-between">
        <div className="flex items-center gap-2 flex-1">
            <SidebarTrigger className="md:hidden" />
            <div className="space-y-1">
                <h1 className="text-2xl font-semibold tracking-tight lg:text-3xl">{title}</h1>
                {description && <p className="text-sm text-muted-foreground">{description}</p>}
            </div>
        </div>
        {children && <div className="shrink-0">{children}</div>}
    </div>
  );
}
