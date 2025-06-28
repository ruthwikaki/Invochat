
'use client';

import { useRouter, useSearchParams, usePathname } from 'next/navigation';
import { Button } from '@/components/ui/button';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { RefreshCw } from 'lucide-react';
import { useCallback, useTransition } from 'react';

export function DashboardHeaderControls() {
  const router = useRouter();
  const pathname = usePathname();
  const searchParams = useSearchParams();
  const [isPending, startTransition] = useTransition();
  const currentRange = searchParams.get('range') || '30d';

  const createQueryString = useCallback(
    (name: string, value: string) => {
      const params = new URLSearchParams(searchParams.toString());
      params.set(name, value);
      return params.toString();
    },
    [searchParams]
  );

  const handleRangeChange = (newRange: string) => {
    startTransition(() => {
        router.push(`${pathname}?${createQueryString('range', newRange)}`);
    });
  };

  const handleRefresh = () => {
    startTransition(() => {
        router.refresh();
    });
  };

  return (
    <div className="flex items-center gap-2">
      <Select value={currentRange} onValueChange={handleRangeChange} disabled={isPending}>
        <SelectTrigger className="w-[180px]">
          <SelectValue placeholder="Select a date range" />
        </SelectTrigger>
        <SelectContent>
          <SelectItem value="7d">Last 7 Days</SelectItem>
          <SelectItem value="30d">Last 30 Days</SelectItem>
          <SelectItem value="90d">Last 90 Days</SelectItem>
        </SelectContent>
      </Select>
      <Button variant="outline" size="icon" onClick={handleRefresh} disabled={isPending}>
        <RefreshCw className={cn("h-4 w-4", isPending && "animate-spin")} />
        <span className="sr-only">Refresh data</span>
      </Button>
    </div>
  );
}
