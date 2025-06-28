
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { UploadCloud, Link as LinkIcon, Bot } from 'lucide-react';
import Link from 'next/link';

export default function ImportPage() {
  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Import & Sync Data</h1>
        </div>
      </div>
      
      <Card>
        <CardHeader>
          <CardTitle>Data Management</CardTitle>
          <CardDescription>
            Your database is now using a modern, multi-table schema. Manual CSV imports are no longer the best way to manage your data.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <p className="text-muted-foreground mb-4">
            We recommend syncing your data directly from your e-commerce platform (like Shopify) or ERP system. This ensures your data in InvoChat is always up-to-date.
          </p>
           <h3 className="font-semibold mt-6 mb-2">Connect a Platform</h3>
           <p className="text-sm text-muted-foreground">
             Connect your Shopify, WooCommerce, or other platforms to automatically sync products, orders, and inventory levels.
           </p>
           <Button variant="secondary" className="mt-4" disabled>
             <LinkIcon className="mr-2 h-4 w-4" />
             Connect to Shopify (Coming Soon)
           </Button>
        </CardContent>
        <CardFooter>
            <p className="text-xs text-muted-foreground">
                Need to perform a one-off data manipulation? Try asking the AI. For example: "Add a new vendor called 'New Supplies Co'."
            </p>
        </CardFooter>
      </Card>
    </div>
  );
}
