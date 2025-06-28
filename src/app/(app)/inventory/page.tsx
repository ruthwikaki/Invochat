
'use client';

import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Bot, Database, Package } from 'lucide-react';
import Link from 'next/link';

export default function ProductsPage() {
  return (
    <div className="p-4 sm:p-6 lg:p-8 space-y-6 flex flex-col items-center justify-center h-full text-center">
       <div className="flex items-center gap-2 absolute top-8 left-8">
        <SidebarTrigger className="md:hidden" />
      </div>

      <Card className="w-full max-w-lg">
        <CardHeader>
            <div className="mx-auto bg-primary/10 p-3 rounded-full w-fit mb-4">
                <Package className="h-8 w-8 text-primary" />
            </div>
            <CardTitle>Your Inventory is Now Smarter</CardTitle>
            <CardDescription>
                With the new database schema, your inventory data is spread across multiple tables like sales, warehouses, and suppliers. A simple list view is no longer sufficient.
            </CardDescription>
        </CardHeader>
        <CardContent>
            <p className="text-muted-foreground mb-4">
               Use the AI chat to ask complex questions and get the insights you need.
            </p>
            <ul className="list-disc pl-5 space-y-2 text-sm text-left">
                <li>"Show me my current inventory value by category."</li>
                <li>"Which items in the 'Main Warehouse' are running low?"</li>
                <li>"Create a table of all items from 'Johnson Supply'."</li>
            </ul>
        </CardContent>
        <CardFooter className="flex-col sm:flex-row gap-2">
            <Button asChild className="w-full sm:w-auto">
                <Link href="/chat">
                    <Bot className="mr-2 h-4 w-4" />
                    Ask InvoChat
                </Link>
            </Button>
            <Button asChild variant="secondary" className="w-full sm:w-auto">
                <Link href="/database">
                    <Database className="mr-2 h-4 w-4" />
                    Explore Raw Tables
                </Link>
            </Button>
        </CardFooter>
      </Card>
    </div>
  );
}
