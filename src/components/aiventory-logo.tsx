
import { cn } from '@/lib/utils';

export function AIventoryLogo({ className }: { className?: string }) {
  return (
    <div className={cn("h-10 w-10 text-primary", className)}>
        <svg viewBox="0 0 24 24" fill="none" className="w-full h-full">
            <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" 
                fill="currentColor" opacity="0.2"/>
            <path d="M12 2L2 7v10c0 5.55 3.84 10.74 9 12 5.16-1.26 9-6.45 9-12V7l-10-5z" 
                stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M12 11.5V16M12 8v.01" 
                stroke="#FFFFFF" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
    </div>
  );
}
