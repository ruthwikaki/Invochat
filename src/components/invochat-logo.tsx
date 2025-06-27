import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 48 48"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
        <path
            d="M8 8C8 6.89543 8.89543 6 10 6H38C39.1046 6 40 6.89543 40 8V34C40 35.1046 39.1046 36 38 36H26L20 42V36H10C8.89543 36 8 35.1046 8 34V8Z"
            fill="hsl(var(--primary))"
        />
        <path
            d="M20 28V20"
            stroke="hsl(var(--primary-foreground))"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
        <path
            d="M28 28V16"
            stroke="hsl(var(--primary-foreground))"
            strokeWidth="2"
            strokeLinecap="round"
            strokeLinejoin="round"
        />
    </svg>
  );
}
