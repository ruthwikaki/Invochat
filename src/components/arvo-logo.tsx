
import { cn } from '@/lib/utils';

export function ArvoLogo({ className }: { className?: string }) {
  return (
    <div className={cn("h-10 w-10 text-primary", className)}>
        <svg viewBox="0 0 24 24" fill="none" className="w-full h-full">
        <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" 
                fill="currentColor" opacity="0.2"/>
        <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" 
                stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        <path d="M8 11h8M12 7v8" 
                stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
    </div>
  );
}
