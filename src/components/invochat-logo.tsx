
import { cn } from '@/lib/utils';

export function ArvoLogo({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-full bg-[#8B5CF6] text-primary-foreground font-bold text-sm',
        className
      )}
    >
      A
    </div>
  );
}
