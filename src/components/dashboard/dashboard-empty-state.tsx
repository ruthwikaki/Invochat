
'use client';

import Link from 'next/link';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card';
import { motion } from 'framer-motion';
import { UploadCloud, FileText } from 'lucide-react';
import { ArvoLogo } from '../arvo-logo';

export function DashboardEmptyState() {
  return (
    <div className="flex items-center justify-center py-12">
      <Card className="w-full max-w-2xl text-center p-8 border-2 border-dashed bg-card/50">
        <motion.div
          initial={{ scale: 0, opacity: 0 }}
          animate={{ scale: 1, opacity: 1 }}
          transition={{ type: 'spring', stiffness: 200, damping: 15, delay: 0.1 }}
          className="mx-auto mb-6"
        >
          <ArvoLogo className="h-20 w-20" />
        </motion.div>
        <CardHeader className="p-0">
          <CardTitle className="text-3xl font-bold">Welcome to ARVO!</CardTitle>
          <CardDescription className="mt-2 text-lg text-muted-foreground">
            Your dashboard is ready. Let's populate it with data.
          </CardDescription>
        </CardHeader>
        <CardContent className="mt-8 space-y-6">
          <p className="max-w-md mx-auto">
            This dashboard will light up with insights, charts, and metrics once you've imported your inventory and sales data. Use our CSV importer to get started.
          </p>
          <div className="flex flex-col sm:flex-row justify-center gap-4">
            <Button asChild size="lg">
              <Link href="/import">
                <UploadCloud className="mr-2 h-5 w-5" /> Import Your Data
              </Link>
            </Button>
            <Button asChild variant="outline" size="lg">
              <Link href="/import">
                <FileText className="mr-2 h-5 w-5" /> View Sample CSVs
              </Link>
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
