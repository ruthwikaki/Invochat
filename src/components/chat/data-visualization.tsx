
'use client';

import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { DataTable } from '@/components/ai-response/data-table';
import { DynamicChart } from '@/components/ai-response/dynamic-chart';
import { Button } from '@/components/ui/button';
import { Expand, Download, X } from 'lucide-react';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogClose } from '@/components/ui/dialog';
import { useState } from 'react';

type DataVisualizationProps = {
  visualization: {
    type: 'table' | 'chart' | 'alert';
    data: Record<string, unknown>[];
    config?: any;
  };
  title?: string;
};

export function DataVisualization({ visualization, title }: DataVisualizationProps) {
  const [isExpanded, setIsExpanded] = useState(false);

  const renderVisualization = (isExpandedView = false) => {
    switch (visualization.type) {
      case 'table':
        return <DataTable data={visualization.data} />;
      case 'chart':
        return (
          <DynamicChart
            chartType={visualization.config.chartType}
            data={visualization.data}
            config={visualization.config}
            isExpanded={isExpandedView}
          />
        );
      default:
        return <p>Unsupported visualization type</p>;
    }
  };

  return (
    <>
      <Card className="mt-2 max-w-full overflow-hidden">
        <CardHeader className="flex flex-row items-center justify-between pb-2">
          <CardTitle className="text-base font-medium">{title || 'Data Visualization'}</CardTitle>
          <div className="flex gap-1">
            <Button
              variant="ghost"
              size="icon"
              className="h-6 w-6"
              onClick={() => setIsExpanded(true)}
              aria-label="Expand chart"
            >
              <Expand className="h-4 w-4" />
            </Button>
            <Button variant="ghost" size="icon" className="h-6 w-6" disabled aria-label="Download chart">
              <Download className="h-4 w-4" />
            </Button>
          </div>
        </CardHeader>
        <CardContent className="h-64">
          {renderVisualization()}
        </CardContent>
      </Card>

      <Dialog open={isExpanded} onOpenChange={setIsExpanded}>
        <DialogContent className="max-w-4xl h-[80vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{title || 'Data Visualization'}</DialogTitle>
             <DialogClose className="absolute right-4 top-4 rounded-sm opacity-70 ring-offset-background transition-opacity hover:opacity-100 focus:outline-none focus:ring-2 focus:ring-ring focus:ring-offset-2 disabled:pointer-events-none data-[state=open]:bg-accent data-[state=open]:text-muted-foreground">
                <X className="h-4 w-4" />
                <span className="sr-only">Close</span>
            </DialogClose>
          </DialogHeader>
          <div className="mt-4 flex-1 h-full">{renderVisualization(true)}</div>
        </DialogContent>
      </Dialog>
    </>
  );
}
