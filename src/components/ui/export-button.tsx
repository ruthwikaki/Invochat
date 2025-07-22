
'use client';

import { useTransition } from 'react';
import { Button } from './button';
import { Download, Loader2 } from 'lucide-react';
import { useToast } from '@/hooks/use-toast';

interface ExportButtonProps {
  exportAction: () => Promise<{ success: boolean; data?: string; error?: string }>;
  filename: string;
}

export function ExportButton({ exportAction, filename }: ExportButtonProps) {
  const [isPending, startTransition] = useTransition();
  const { toast } = useToast();

  const handleExport = () => {
    startTransition(async () => {
      const result = await exportAction();
      if (result.success && result.data) {
        // Create a blob from the CSV data
        const blob = new Blob([result.data], { type: 'text/csv;charset=utf-8;' });
        const url = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.setAttribute('href', url);
        link.setAttribute('download', filename);
        link.style.visibility = 'hidden';
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        toast({ title: 'Export Complete', description: `${filename} has been downloaded.` });
      } else {
        toast({
          variant: 'destructive',
          title: 'Export Failed',
          description: result.error || 'Could not export data.',
        });
      }
    });
  };

  return (
    <Button variant="outline" onClick={handleExport} disabled={isPending}>
      {isPending ? (
        <Loader2 className="mr-2 h-4 w-4 animate-spin" />
      ) : (
        <Download className="mr-2 h-4 w-4" />
      )}
      Export
    </Button>
  );
}
    