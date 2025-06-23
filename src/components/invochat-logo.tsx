import { cn } from '@/lib/utils';

export function InvoChatLogo({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground font-bold text-sm',
        className
      )}
    >
      DW
    </div>
  );
}
