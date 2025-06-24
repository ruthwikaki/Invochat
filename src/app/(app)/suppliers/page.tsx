
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { Mail, Briefcase } from 'lucide-react';
import { getSuppliersData } from '@/app/data-actions';
import type { Vendor } from '@/types';

export default async function SuppliersPage() {
  const vendors: Vendor[] = await getSuppliersData();

  return (
    <div className="animate-fade-in p-4 sm:p-6 lg:p-8 space-y-6">
       <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <SidebarTrigger className="md:hidden" />
            <h1 className="text-2xl font-semibold">Suppliers</h1>
          </div>
          <Button>Add New Supplier</Button>
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {vendors.map((vendor) => (
          <Card key={vendor.id}>
            <CardHeader className="flex flex-row items-center gap-4">
              <Avatar className="h-12 w-12">
                <AvatarFallback>{vendor.vendor_name.charAt(0)}</AvatarFallback>
              </Avatar>
              <div className="flex-1">
                <CardTitle>{vendor.vendor_name}</CardTitle>
                <CardDescription>{vendor.address}</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex items-center text-sm">
                <Mail className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>{vendor.contact_info}</span>
              </div>
              <div className="flex items-center text-sm">
                <Briefcase className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>Terms: {vendor.terms}</span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
