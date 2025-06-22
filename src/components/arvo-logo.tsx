import { cn } from '@/lib/utils';
import { MessageSquare } from 'lucide-react';

export function ArvoLogo({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground',
        className
      )}
    >
      <MessageSquare className="h-5 w-5" />
    </div>
  );
}
