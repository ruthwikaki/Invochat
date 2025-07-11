
import { getProductLifecycleAnalysis } from '@/app/data-actions';
import { ProductLifecycleClientPage } from '@/components/reports/product-lifecycle-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default async function ProductLifecyclePage() {
  const data = await getProductLifecycleAnalysis();

  return (
    <AppPage>
      <AppPageHeader
        title="Product Lifecycle Analysis"
        description="Understand where each product is in its lifecycle to make better strategic decisions."
      />
      <ProductLifecycleClientPage initialData={data} />
    </AppPage>
  );
}
