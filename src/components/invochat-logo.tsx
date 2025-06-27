import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
        <rect x="3" y="11" width="18" height="8" rx="2" fill="hsl(var(--primary))" fillOpacity="0.5" />
        <rect x="5" y="7" width="14" height="8" rx="2" fill="hsl(var(--primary))" fillOpacity="0.7" />
        <rect x="7" y="3" width="10" height="8" rx="2" fill="hsl(var(--primary))" />
    </svg>
  );
}
