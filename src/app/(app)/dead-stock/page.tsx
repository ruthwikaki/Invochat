
import { getDeadStockPageData } from '@/app/data-actions';
import { AppPageHeader } from '@/components/ui/page';
import { DeadStockClientPage } from './dead-stock-client-page';

export const dynamic = 'force-dynamic';

export default async function DeadStockPage() {
    const deadStockData = await getDeadStockPageData();

    return (
        <>
            <AppPageHeader
                title="Dead Stock Analysis"
                description="Identify money trapped in slow-moving inventory."
            />
            <DeadStockClientPage initialData={deadStockData} />
        </>
    );
}
