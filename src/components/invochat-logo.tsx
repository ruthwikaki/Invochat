
import { cn } from '@/lib/utils';

export function InvoChatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 150 150"
      xmlns="http://www.w3.org/2000/svg"
      fill="currentColor"
    >
      <path
        d="M75,0 L150,150 L0,150 Z M75,40 L105,110 L45,110 Z"
        fillRule="evenodd"
      />
    </svg>
  );
}
