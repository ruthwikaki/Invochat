

'use client';

import { useState, useMemo } from 'react';
import type { CustomerSegmentAnalysisItem } from '@/types';
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from '@/components/ui/card';
import { DataTable } from '@/components/ai-response/data-table';
import { Users, UserPlus, Repeat, Trophy, BrainCircuit, ArrowRight } from 'lucide-react';
import { formatCentsAsCurrency } from '@/lib/utils';
import { AnimatePresence, motion } from 'framer-motion';
import { Button } from '../ui/button';
import Link from 'next/link';

interface CustomerSegmentClientPageProps {
  initialData: CustomerSegmentAnalysisItem[];
  initialInsights: { analysis: string; suggestion: string } | null;
}

const segmentConfig = {
  'New Customers': { icon: UserPlus, description: 'Top products driving customer acquisition.' },
  'Repeat Customers': { icon: Repeat, description: 'Products that encourage loyalty and repeat business.' },
  'Top Spenders': { icon: Trophy, description: 'High-value products favored by your most valuable customers.' },
};

export function CustomerSegmentClientPage({ initialData, initialInsights }: CustomerSegmentClientPageProps) {
  const [data] = useState(initialData);
  const [insights] = useState(initialInsights);

  const segments = useMemo(() => {
    const grouped: Record<string, CustomerSegmentAnalysisItem[]> = {
      'New Customers': [],
      'Repeat Customers': [],
      'Top Spenders': [],
    };
    data.forEach(item => {
      if (grouped[item.segment]) {
        grouped[item.segment].push(item);
      }
    });
    return grouped;
  }, [data]);
  
  const hasData = data.length > 0;

  return (
    <div className="space-y-6">
      {!hasData ? (
        <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
            <motion.div
                initial={{ scale: 0.8, opacity: 0 }}
                animate={{ scale: 1, opacity: 1 }}
                transition={{ delay: 0.1, type: 'spring', stiffness: 200, damping: 10 }}
                className="relative bg-primary/10 rounded-full p-6"
            >
                <Users className="h-16 w-16 text-primary" />
            </motion.div>
            <h3 className="mt-6 text-xl font-semibold">Not Enough Data</h3>
            <p className="mt-2 text-muted-foreground max-w-md">
                This report requires sufficient sales history with identifiable customers to generate insights.
            </p>
        </Card>
      ) : (
        <>
            {insights && (
                <Card className="bg-primary/10 border-primary/20">
                    <CardHeader>
                        <CardTitle className="flex items-center gap-2"><BrainCircuit className="h-5 w-5 text-primary" /> AI-Powered Insights</CardTitle>
                    </CardHeader>
                    <CardContent>
                        <p className="font-semibold">{insights.analysis}</p>
                        <div className="mt-4 flex items-center justify-between p-3 bg-muted/50 rounded-lg">
                            <div>
                                <h4 className="font-semibold">Suggested Action</h4>
                                <p className="text-sm text-muted-foreground">{insights.suggestion}</p>
                            </div>
                            <Button asChild>
                                <Link href={`/chat?q=${encodeURIComponent(insights.suggestion)}`}>Ask AI to help <ArrowRight className="ml-2 h-4 w-4" /></Link>
                            </Button>
                        </div>
                    </CardContent>
                </Card>
            )}
            <AnimatePresence>
                {Object.entries(segments).map(([segmentName, segmentData], index) => {
                    if (segmentData.length === 0) return null;
                    
                    const config = segmentConfig[segmentName as keyof typeof segmentConfig];
                    const formattedData = segmentData.map(item => ({
                        SKU: item.sku,
                        'Product Name': item.product_name,
                        'Total Quantity': item.total_quantity,
                        'Total Revenue': formatCentsAsCurrency(item.total_revenue),
                    }));

                    return (
                        <motion.div
                            key={segmentName}
                            initial={{ opacity: 0, y: 50 }}
                            animate={{ opacity: 1, y: 0 }}
                            transition={{ duration: 0.5, delay: index * 0.1 }}
                        >
                            <Card>
                                <CardHeader>
                                    <CardTitle className="flex items-center gap-2">
                                        <config.icon className="h-5 w-5 text-primary" />
                                        {segmentName}
                                    </CardTitle>
                                    <CardDescription>{config.description}</CardDescription>
                                </CardHeader>
                                <CardContent>
                                    <DataTable data={formattedData} />
                                </CardContent>
                            </Card>
                        </motion.div>
                    );
                })}
            </AnimatePresence>
        </>
      )}
    </div>
  );
}
