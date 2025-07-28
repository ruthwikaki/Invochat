'use client';

import Link from 'next/link';
import { usePathname } from 'next/navigation';
import { cn } from '@/lib/utils';
import { buttonVariants } from '@/components/ui/button';

const navItems = [
  { href: '/settings/profile', label: 'Profile' },
  { href: '/settings/integrations', label: 'Integrations' },
  { href: '/settings/export', label: 'Export Data' },
  { href: '/settings/audit-log', label: 'Audit Log' },
];

export function SettingsNav() {
  const pathname = usePathname();

  return (
    <nav className="flex flex-col space-y-1">
      {navItems.map(item => (
        <Link
          key={item.href}
          href={item.href}
          className={cn(
            buttonVariants({ variant: 'ghost' }),
            pathname === item.href
              ? 'bg-muted hover:bg-muted'
              : 'hover:bg-transparent hover:underline',
            'justify-start'
          )}
        >
          {item.label}
        </Link>
      ))}
    </nav>
  );
}
