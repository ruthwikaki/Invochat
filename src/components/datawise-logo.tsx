import { cn } from '@/lib/utils';
import { Bot } from 'lucide-react';

export function DatawiseLogo({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-lg bg-primary text-primary-foreground',
        className
      )}
    >
      <Bot className="h-5 w-5" />
    </div>
  );
}
