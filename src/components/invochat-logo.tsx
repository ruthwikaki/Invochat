import { cn } from '@/lib/utils';

export function InvochatLogo({ className }: { className?: string }) {
  return (
    <svg
      role="img"
      aria-label="InvoChat Logo"
      className={cn(className)}
      viewBox="0 0 256 256"
      xmlns="http://www.w3.org/2000/svg"
    >
      <g stroke="currentColor" strokeLinecap="round" strokeLinejoin="round" strokeWidth="12" fill="none">
        {/* Head */}
        <path d="M184 64H72C63.1634 64 56 71.1634 56 80V124C56 132.837 63.1634 140 72 140H163.515C164.838 140 166.121 139.468 167.094 138.529L176.688 129.282C178.502 127.531 181.498 127.531 183.312 129.282L192.906 138.529C193.879 139.468 195.162 140 196.485 140H200" />
        <path fill="currentColor" fillRule="evenodd" clipRule="evenodd" d="M172 80H84C79.5817 80 76 83.5817 76 88V108C76 112.418 79.5817 116 84 116H172C176.418 116 180 112.418 180 108V88C180 83.5817 176.418 80 172 80ZM104 98C104 95.7909 102.209 94 100 94C97.7909 94 96 95.7909 96 98C96 100.209 97.7909 102 100 102C102.209 102 104 100.209 104 98ZM156 98C156 100.209 157.791 102 160 102C162.209 102 164 100.209 164 98C164 95.7909 162.209 94 160 94C157.791 94 156 95.7909 156 98Z" />

        {/* Antenna */}
        <circle cx="128" cy="24" r="6" fill="currentColor" stroke="none"/>
        <path d="M128 48V30" />

        {/* Body & Arms */}
        <path d="M188 172C188 163.163 180.837 156 172 156H84C75.1634 156 68 163.163 68 172V196C68 211.464 80.536 224 96 224H160C175.464 224 188 211.464 188 196V172Z" />

        {/* Cube */}
        <path d="M128 176L104 188V208L128 220L152 208V188L128 176Z" stroke="white" strokeWidth="8"/>
        <path d="M104 188L128 200L152 188" stroke="white" strokeWidth="8"/>
      </g>
    </svg>
  );
}
