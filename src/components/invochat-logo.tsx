import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 256 256"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
    >
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="12">
        {/* Head */}
        <rect x="64" y="48" width="128" height="80" rx="16" />
        
        {/* Eyes */}
        <circle cx="104" cy="88" r="8" fill="currentColor" stroke="none"/>
        <circle cx="152" cy="88" r="8" fill="currentColor" stroke="none"/>
        
        {/* Antennae */}
        <path d="M96 48V32" />
        <circle cx="96" cy="28" r="8" fill="currentColor" stroke="none" />
        <path d="M160 48V32" />
        <circle cx="160" cy="28" r="8" fill="currentColor" stroke="none" />
        
        {/* Body */}
        <rect x="40" y="128" width="176" height="88" rx="16" />

        {/* Screen with Chart */}
        <rect x="64" y="144" width="128" height="56" rx="4" strokeWidth="8" />
        <path d="M88 184V160" strokeWidth="12" />
        <path d="M128 184V168" strokeWidth="12" />
        <path d="M168 184V152" strokeWidth="12" />

        {/* Arms */}
        <path d="M40 152H24" />
        <path d="M216 152H200" />
        <circle cx="20" cy="152" r="8" fill="currentColor" stroke="none"/>
        <circle cx="236" cy="152" r="8" fill="currentColor" stroke="none"/>
        
        {/* Legs */}
        <path d="M96 216V232" />
        <path d="M160 216V232" />
        
        {/* Feet */}
        <path d="M80 232a16 16 0 1 1 32 0a16 16 0 1 1 -32 0" fill="currentColor" stroke="none" />
        <path d="M144 232a16 16 0 1 1 32 0a16 16 0 1 1 -32 0" fill="currentColor" stroke="none"/>
    </g>
    </svg>
  );
}
