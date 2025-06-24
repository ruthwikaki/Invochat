
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
import { Mail, Briefcase, DollarSign, Truck, Package } from 'lucide-react';
import { getSuppliersData } from '@/app/data-actions';
import type { Supplier } from '@/types';
import { Badge } from '@/components/ui/badge';

export default async function SuppliersPage() {
  let suppliers: Supplier[] = [];

  try {
    suppliers = await getSuppliersData();
  } catch (error) {
    console.error("Failed to fetch suppliers data:", error);
  }

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
        {suppliers.map((supplier) => (
          <Card key={supplier.id}>
            <CardHeader className="flex flex-row items-center gap-4">
              <Avatar className="h-12 w-12">
                <AvatarFallback>{supplier.name.charAt(0)}</AvatarFallback>
              </Avatar>
              <div className="flex-1">
                <CardTitle>{supplier.name}</CardTitle>
                <CardDescription>{supplier.address}</CardDescription>
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
               <div className="flex items-center">
                <DollarSign className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>Total Spend: ${supplier.totalSpend.toLocaleString()}</span>
              </div>
               <div className="flex items-center">
                <Truck className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>On-Time Rate: {supplier.onTimeDeliveryRate}%</span>
              </div>
            </CardContent>
             <CardFooter className="flex-col items-start gap-2">
                <div className="flex items-center text-sm">
                    <Package className="h-4 w-4 mr-2 text-muted-foreground" />
                    <span>Items Supplied:</span>
                </div>
                <div className="flex flex-wrap gap-1">
                    {supplier.itemsSupplied.slice(0, 5).map(item => (
                        <Badge key={item} variant="secondary">{item}</Badge>
                    ))}
                    {supplier.itemsSupplied.length > 5 && (
                        <Badge variant="outline">+{supplier.itemsSupplied.length - 5} more</Badge>
                    )}
                </div>
             </CardFooter>
          </Card>
        ))}
      </div>
    </div>
  );
}
