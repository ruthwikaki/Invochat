'use client';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import { Button } from '@/components/ui/button';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Progress } from '@/components/ui/progress';
import { SidebarTrigger } from '@/components/ui/sidebar';
import { mockSuppliers } from '@/lib/mock-data';
import { Mail, Truck } from 'lucide-react';

export default function SuppliersPage() {
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
        {mockSuppliers.map((supplier) => (
          <Card key={supplier.id}>
            <CardHeader className="flex flex-row items-center gap-4">
              <Avatar className="h-12 w-12">
                <AvatarFallback>{supplier.name.charAt(0)}</AvatarFallback>
              </Avatar>
              <div className="flex-1">
                <CardTitle>{supplier.name}</CardTitle>
                <CardDescription>ID: {supplier.id}</CardDescription>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <div>
                <div className="flex justify-between text-sm mb-1">
                  <span className="text-muted-foreground">On-Time Delivery</span>
                  <span className="font-medium">{supplier.onTimeDeliveryRate}%</span>
                </div>
                <Progress value={supplier.onTimeDeliveryRate} className="h-2" />
              </div>
              <div className="flex items-center text-sm">
                <Truck className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>Avg. delivery: {supplier.avgDeliveryTime} days</span>
              </div>
               <div className="flex items-center text-sm">
                <Mail className="h-4 w-4 mr-2 text-muted-foreground" />
                <span>{supplier.contact}</span>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </div>
  );
}
