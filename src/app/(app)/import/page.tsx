
'use client';

import { Button } from '@/components/ui/button';
import { Card, CardContent, CardDescription, CardHeader, CardTitle, CardFooter } from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Link as LinkIcon, Bot, PlusCircle } from 'lucide-react';
import Link from 'next/link';

export default function ConnectionsPage() {
  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6">
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <SidebarTrigger className="md:hidden" />
          <h1 className="text-2xl font-semibold">Data Connections</h1>
        </div>
        <Button disabled>
            <PlusCircle className="mr-2 h-4 w-4" />
            Add Connection
        </Button>
      </div>
      
      <Card>
        <CardHeader>
          <CardTitle>Connect Your Platforms</CardTitle>
          <CardDescription>
            Sync your data directly from your e-commerce platforms or marketplaces to keep InvoChat up-to-date automatically.
          </CardDescription>
        </CardHeader>
        <CardContent>
           <div className="border rounded-lg p-4 flex items-center justify-between">
                <div>
                    <h3 className="font-semibold text-lg">Shopify</h3>
                    <p className="text-sm text-muted-foreground">Sync products, orders, and inventory from your Shopify store.</p>
                </div>
                <Button variant="secondary" disabled>
                    <LinkIcon className="mr-2 h-4 w-4" />
                    Connect (Coming Soon)
                </Button>
           </div>
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
