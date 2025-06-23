import { cn } from '@/lib/utils';
import { BarChart3 } from 'lucide-react';

export function DatawiseLogo({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        'flex h-8 w-8 items-center justify-center rounded-lg bg-[#3F51B5] text-primary-foreground',
        className
      )}
    >
      <BarChart3 className="h-5 w-5" />
    </div>
  );
}
