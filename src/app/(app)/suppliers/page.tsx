
'use client';

import { useState, useEffect, useMemo } from 'react';
import { Avatar, AvatarFallback } from '@/components/ui/avatar';
import {
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '@/components/ui/card';
import { Mail, Briefcase, FileText, Truck, Search, AlertTriangle } from 'lucide-react';
import { getSuppliersData } from '@/app/data-actions';
import type { Supplier } from '@/types';
import { Input } from '@/components/ui/input';
import { useToast } from '@/hooks/use-toast';
import { Skeleton } from '@/components/ui/skeleton';
import { getErrorMessage } from '@/lib/error-handler';
import { AppPage, AppPageHeader } from '@/components/ui/page';

function SupplierCard({ supplier }: { supplier: Supplier }) {
  return (
    <Card>
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
        <a href={`mailto:${supplier.contact_info}`} className="flex items-center hover:underline text-primary">
          <Mail className="h-4 w-4 mr-2 text-muted-foreground" />
          <span>{supplier.contact_info}</span>
        </a>
        <div className="flex items-center">
          <Briefcase className="h-4 w-4 mr-2 text-muted-foreground" />
          <span>Terms: {supplier.terms || 'N/A'}</span>
        </div>
        {supplier.account_number && (
          <div className="flex items-center">
            <FileText className="h-4 w-4 mr-2 text-muted-foreground" />
            <span>Account: {supplier.account_number}</span>
          </div>
        )}
      </CardContent>
    </Card>
  );
}

function LoadingState() {
    return (
        <>
            {Array.from({ length: 3 }).map((_, i) => (
                <Card key={i}>
                    <CardHeader className="flex flex-row items-center gap-4">
                        <Skeleton className="h-12 w-12 rounded-full" />
                        <div className="flex-1 space-y-2">
                            <Skeleton className="h-5 w-3/4" />
                            <Skeleton className="h-4 w-1/2" />
                        </div>
                    </CardHeader>
                    <CardContent className="space-y-4">
                         <Skeleton className="h-5 w-full" />
                         <Skeleton className="h-5 w-2/3" />
                    </CardContent>
                </Card>
            ))}
        </>
    )
}

export default function SuppliersPage() {
  const [suppliers, setSuppliers] = useState<Supplier[]>([]);
  const [loading, setLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');
  const { toast } = useToast();

  useEffect(() => {
    async function fetchData() {
      try {
        setLoading(true);
        const data = await getSuppliersData();
        setSuppliers(data);
      } catch (error) {
        toast({
          variant: 'destructive',
          title: 'Error Loading Suppliers',
          description: getErrorMessage(error) || 'Could not load supplier data.',
        });
      } finally {
        setLoading(false);
      }
    }
    fetchData();
  }, [toast]);

  const filteredSuppliers = useMemo(() => {
    if (!searchTerm) return suppliers;
    return suppliers.filter(supplier =>
      supplier.name.toLowerCase().includes(searchTerm.toLowerCase()) ||
      (supplier.contact_info && supplier.contact_info.toLowerCase().includes(searchTerm.toLowerCase())) ||
      (supplier.account_number && supplier.account_number.includes(searchTerm))
    );
  }, [suppliers, searchTerm]);

  return (
    <AppPage>
       <AppPageHeader title="Suppliers">
          <div className="relative w-full max-w-sm">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
            <Input
              placeholder="Search by name, email, or account..."
              className="pl-10"
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
            />
          </div>
      </AppPageHeader>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {loading ? (
          <LoadingState />
        ) : filteredSuppliers.length > 0 ? (
          filteredSuppliers.map((supplier) => (
            <SupplierCard key={supplier.id} supplier={supplier} />
          ))
        ) : (
          <div className="col-span-full">
            <Card className="h-60 flex flex-col items-center justify-center text-center border-2 border-dashed">
                <Truck className="h-12 w-12 text-muted-foreground" />
                <h3 className="mt-4 text-lg font-semibold">No Suppliers Found</h3>
                <p className="text-muted-foreground">
                    {suppliers.length > 0 ? "No suppliers match your search." : "Import supplier data to see it here."}
                </p>
            </Card>
          </div>
        )}
      </div>

       <Card className="bg-muted/50 border-dashed">
            <CardHeader>
                <CardTitle className="flex items-center gap-2 text-muted-foreground">
                    <AlertTriangle className="h-5 w-5" />
                    Under Development
                </CardTitle>
                <CardDescription>
                    Thanks for your feedback! Here's what's coming next for this page:
                </CardDescription>
            </CardHeader>
            <CardContent>
                 <ul className="list-disc pl-5 space-y-2 text-sm text-muted-foreground">
                    <li><strong>Performance Metrics:</strong> I need to adjust the database to link products to suppliers before I can show performance data.</li>
                    <li><strong>CRUD Actions:</strong> The ability to add, edit, and delete suppliers directly from this page is a top priority.</li>
                </ul>
            </CardContent>
        </Card>
    </AppPage>
  );
}
