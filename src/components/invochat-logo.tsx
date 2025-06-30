
import { cn } from '@/lib/utils';

export function InvoChatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      viewBox="0 0 24 24"
      xmlns="http://www.w3.org/2000/svg"
      className={cn('fill-current', className)}
    >
      <path
        d="M21.53,6.32,14.6,2.45a4.33,4.33,0,0,0-5.13,0L2.47,6.32a4.33,4.33,0,0,0-2.2,3.81V13.8a4.3,4.3,0,0,0,2.2,3.81l6.94,3.87a4.33,4.33,0,0,0,5.13,0l6.94-3.87a4.3,4.3,0,0,0,2.2-3.81V10.13A4.33,4.33,0,0,0,21.53,6.32ZM8.6,17.47a1,1,0,0,1-1.44-.32L3,10.13a1,1,0,0,1,1.73-1L8.6,15.68a1,1,0,0,1,0,1.15A1,1,0,0,1,8.6,17.47ZM12,14.2a3.15,3.15,0,1,1,3.15-3.15A3.15,3.15,0,0,1,12,14.2Zm7-2.34a1,1,0,0,1-1.73,1l-4-6.94a1,1,0,0,1,1.73-1l4,6.94Z"
      />
    </svg>
  );
}
