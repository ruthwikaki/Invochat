
'use client';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function PurchaseOrdersPage() {
    return (
        <AppPage>
            <AppPageHeader 
                title="Feature Removed"
                description="Purchase Order management has been removed to focus on inventory intelligence."
            />
            <div className="text-center text-muted-foreground p-8 border-2 border-dashed rounded-lg">
                <h3 className="text-lg font-semibold">This feature is no longer available.</h3>
                <p>We are focusing on telling you what to order, not managing the ordering process itself.</p>
                <p className="mt-2">Please use the Reorder Report for actionable insights.</p>
            </div>
        </AppPage>
    );
}
