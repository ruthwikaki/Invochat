

'use client';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function LocationsPage() {
    return (
        <AppPage>
            <AppPageHeader 
                title="Feature Removed"
                description="Multi-location inventory management has been removed for simplification."
            />
            <div className="text-center text-muted-foreground p-8 border-2 border-dashed rounded-lg">
                <h3 className="text-lg font-semibold">This feature is no longer available.</h3>
                <p>To better serve our core users, we have simplified inventory to a single location model.</p>
            </div>
        </AppPage>
    );
}
