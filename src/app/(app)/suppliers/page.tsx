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
import { Mail, Truck } from 'lucide-react';
import { useState, useEffect } from 'react';
import { getSuppliersData } from '@/app/data-actions';
import { useAuth } from '@/context/auth-context';
import { useToast } from '@/hooks/use-toast';
import type { Supplier } from '@/types';
import { Skeleton } from '@/components/ui/skeleton';


export default function SuppliersPage() {
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [loading, setLoading] = useState(true);
  const { user, session } = useAuth();
  const { toast } = useToast();

  useEffect(() => {
    if (user && session) {
      const fetchData = async () => {
        setLoading(true);
        try {
          const token = session.access_token;
          const data = await getSuppliersData(token);
          setSuppliers(data);
        } catch (error) {
          console.error("Failed to fetch suppliers:", error);
          toast({ variant: 'destructive', title: 'Error', description: 'Could not load supplier data.' });
        } finally {
          setLoading(false);
        }
      };
      fetchData();
    }
  }, [user, session, toast]);

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
        {loading ? (
          Array.from({ length: 3 }).map((_, i) => (
            <Card key={i}>
              <CardHeader className="flex flex-row items-center gap-4">
                <Skeleton className="h-12 w-12 rounded-full" />
                <div className="flex-1 space-y-2">
                  <Skeleton className="h-5 w-3/4" />
                  <Skeleton className="h-4 w-1/4" />
                </div>
              </CardHeader>
              <CardContent className="space-y-4">
                <Skeleton className="h-6 w-full" />
                <Skeleton className="h-4 w-2/3" />
                <Skeleton className="h-4 w-3/4" />
              </CardContent>
            </Card>
          ))
        ) : (
          suppliers.map((supplier) => (
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
          ))
        )}
      </div>
    </div>
  );
}
