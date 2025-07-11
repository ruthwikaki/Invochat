
'use client';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';
import Link from 'next/link';

// This is a placeholder as the data fetching and client page will be implemented later.
export default function PurchaseOrdersPage() {
    return (
        <AppPage>
            <AppPageHeader 
                title="Purchase Orders"
                description="Create, manage, and track your incoming inventory."
            >
                 <Button asChild>
                    <Link href="/purchase-orders/new">
                        <Plus className="mr-2 h-4 w-4" />
                        New PO
                    </Link>
                </Button>
            </AppPageHeader>
            <div className="text-center text-muted-foreground p-8 border-2 border-dashed rounded-lg">
                <h3 className="text-lg font-semibold">Coming Soon</h3>
                <p>Purchase Order management is under construction.</p>
            </div>
        </AppPage>
    );
}
