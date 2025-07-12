

import { getCustomerSegmentAnalysis } from '@/app/data-actions';
import { CustomerSegmentClientPage } from '@/components/reports/customer-segment-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function CustomerSegmentsPage() {
  const data = await getCustomerSegmentAnalysis();

  return (
    <AppPage>
      <AppPageHeader
        title="Customer Segment Analysis"
        description="Discover which products are most popular with different types of customers."
      />
      <CustomerSegmentClientPage initialData={data.segments} initialInsights={data.insights} />
    </AppPage>
  );
}
