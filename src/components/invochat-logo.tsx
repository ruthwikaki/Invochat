import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="ARVO Analyst Logo"
      className={cn(className)}
      viewBox="0 0 256 256"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g
        stroke="currentColor"
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth="20"
      >
        {/* Left leg of 'A' / First bar */}
        <path d="M64 208V112" />
        {/* Middle leg of 'A' / Tallest bar */}
        <path d="M128 208V48" />
        {/* Right leg of 'A' / Second bar */}
        <path d="M192 208V144" />
        {/* Crossbar of 'A' */}
        <path d="M44 112L128 48L212 112" fill="none" strokeWidth="16" />
      </g>
    </svg>
  );
}
