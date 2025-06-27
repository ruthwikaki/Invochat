import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="Robot Cube Logo"
      className={cn(className)}
      viewBox="0 0 256 256"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="16">
        {/* Antenna */}
        <path d="M128 48V72" />
        <circle cx="128" cy="48" r="8" fill="currentColor" />

        {/* Head Outline */}
        <rect x="88" y="72" width="80" height="64" rx="24" fill="none" />

        {/* Face Bubble */}
        <path
          d="M104 96h48a8 8 0 0 1 8 8v16a8 8 0 0 1-8 8h-40l-8 8v-8a8 8 0 0 1-8-8v-16a8 8 0 0 1 8-8z"
          fill="currentColor"
        />

        {/* Eyes */}
        <circle cx="116" cy="108" r="6" fill="white" />
        <circle cx="140" cy="108" r="6" fill="white" />

        {/* Body Outline */}
        <rect x="48" y="136" width="160" height="72" rx="36" fill="none" />

        {/* Arms */}
        <path d="M48 168v16a8 8 0 0 0 8 8" />
        <path d="M208 168v16a8 8 0 0 1-8 8" />

        {/* Cube in Hands */}
        <g transform="translate(128, 184)">
          <path d="M-20 -8 L0 -20 L20 -8 L20 12 L0 24 L-20 12 Z" fill="none" />
          <path d="M-20 -8 L0 -20 L0 4" />
          <path d="M0 -20 L20 -8 L20 12 L0 24" />
        </g>
      </g>
    </svg>
  );
}
