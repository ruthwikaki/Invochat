
import { cn } from '@/lib/utils';

export function InvoChatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 24 24"
      fill="currentColor"
      xmlns="http://www.w3.org/2000/svg"
    >
        <path d="M12 2L2 22h20L12 2zm0 4.5L17.5 20h-11L12 6.5z"/>
    </svg>
  );
}
