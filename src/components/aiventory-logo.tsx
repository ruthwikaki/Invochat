
import { cn } from '@/lib/utils';

export function AIventoryLogo({ className }: { className?: string }) {
  return (
    <div className={cn("h-10 w-10 text-primary", className)}>
        <svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg" className="w-full h-full">
            <path d="M12 2L3 7.5V16.5L12 22L21 16.5V7.5L12 2Z" fill="currentColor" opacity="0.2"/>
            <path d="M12 2L21 7.5V16.5L12 22L3 16.5V7.5L12 2Z" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M12 22V12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M21 7.5L12 12L3 7.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M7.5 9.75L12 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
            <path d="M16.5 9.75L12 12" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
    </div>
  );
}
