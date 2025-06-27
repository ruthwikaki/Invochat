import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="Robot Cube Logo"
      className={cn(className)}
      viewBox="0 0 256 256"
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
    >
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="8">
        {/* Antenna */}
        <path d="M128 48V72" />
        <circle cx="128" cy="44" r="8" fill="currentColor" />
        
        {/* Head */}
        <rect x="88" y="72" width="80" height="64" rx="24" fill="currentColor" />
        
        {/* Face (speech bubble) */}
        <path d="M104 96h48a8 8 0 0 1 8 8v16a8 8 0 0 1-8 8h-40l-8 8v-8a8 8 0 0 1-8-8v-16a8 8 0 0 1 8-8z" fill="white" />
        
        {/* Eyes */}
        <circle cx="116" cy="108" r="6" fill="currentColor" />
        <circle cx="140" cy="108" r="6" fill="currentColor" />
        
        {/* Body */}
        <path d="M88 136a40 40 0 0 0-40 40v24a16 16 0 0 0 16 16h128a16 16 0 0 0 16-16v-24a40 40 0 0 0-40-40z" fill="currentColor" />
        
        {/* Arms */}
        <path d="M48 168a8 8 0 0 0-8 8v16a8 8 0 0 0 8 8" fill="currentColor" />
        <path d="M208 168a8 8 0 0 1 8 8v16a8 8 0 0 1-8 8" fill="currentColor" />
        
        {/* Cube in hands */}
        <g transform="translate(128, 184)">
          {/* Cube faces */}
          <path d="M-20 -8 L0 -20 L20 -8 L20 12 L0 24 L-20 12 Z" fill="white" stroke="currentColor" strokeWidth="6" />
          <path d="M-20 -8 L0 -20 L0 4" stroke="currentColor" strokeWidth="6" />
          <path d="M0 -20 L20 -8 L20 12 L0 24" stroke="currentColor" strokeWidth="6" />
        </g>
      </g>
    </svg>
  );
}
