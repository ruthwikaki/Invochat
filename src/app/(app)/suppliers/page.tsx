
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
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
import { Mail, Briefcase, FileText } from 'lucide-react';
import { getSuppliersData } from '@/app/data-actions';
import type { Supplier } from '@/types';

export default async function SuppliersPage() {
  // This page now throws an error if data fetching fails,
  // which will be caught by the `error.tsx` boundary.
  const suppliers: Supplier[] = await getSuppliersData();

  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <SidebarTrigger className="md:hidden" />
            <h1 className="text-2xl font-semibold">Suppliers</h1>
          </div>
          <Button disabled>Add New Supplier</Button>
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {suppliers.length === 0 ? (
          <p className="col-span-full text-center text-muted-foreground">No suppliers found.</p>
        ) : (
          suppliers.map((supplier) => (
            <Card key={supplier.id}>
              <CardHeader className="flex flex-row items-center gap-4">
                <Avatar className="h-12 w-12">
                  <AvatarFallback>{supplier.name.charAt(0)}</AvatarFallback>
                </Avatar>
                <div className="flex-1">
                  <CardTitle>{supplier.name}</CardTitle>
                  <CardDescription>{supplier.address || 'Address not available'}</CardDescription>
                </div>
              </CardHeader>
              <CardContent className="space-y-4 text-sm">
                <div className="flex items-center">
                  <Mail className="h-4 w-4 mr-2 text-muted-foreground" />
                  <span>{supplier.contact_info}</span>
                </div>
                <div className="flex items-center">
                  <Briefcase className="h-4 w-4 mr-2 text-muted-foreground" />
                  <span>Terms: {supplier.terms}</span>
                </div>
                {supplier.account_number && (
                  <div className="flex items-center">
                    <FileText className="h-4 w-4 mr-2 text-muted-foreground" />
                    <span>Account: {supplier.account_number}</span>
                  </div>
                )}
              </CardContent>
               <CardFooter>
                 <p className="text-xs text-muted-foreground">Performance metrics are coming soon.</p>
              </CardFooter>
            </Card>
          ))
        )}
      </div>
    </div>
  );
}
