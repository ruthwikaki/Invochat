
import { SupplierForm } from '@/components/suppliers/supplier-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function NewSupplierPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Create New Supplier"
        description="Add a new supplier to your system."
      />
      <SupplierForm />
    </AppPage>
  );
}
