
import { getPurchaseOrderById } from '@/app/data-actions';
import { notFound } from 'next/navigation';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { PurchaseOrderDetailsClientPage } from './po-details-client-page';
import { Button } from '@/components/ui/button';
import Link from 'next/link';
import { ArrowLeft } from 'lucide-react';

export default async function PurchaseOrderDetailsPage({ params }: { params: { id: string }}) {
    const po = await getPurchaseOrderById(params.id);

    if (!po) {
        notFound();
    }

    return (
        <AppPage>
            <AppPageHeader 
                title={`Purchase Order #${po.po_number}`}
                description={`Details for PO created on ${new Date(po.order_date).toLocaleDateString()}`}
            >
                 <Button asChild variant="outline">
                    <Link href="/purchase-orders">
                        <ArrowLeft className="mr-2 h-4 w-4" />
                        Back to All POs
                    </Link>
                </Button>
            </AppPageHeader>
            <PurchaseOrderDetailsClientPage initialPurchaseOrder={po} />
        </AppPage>
    );
}
