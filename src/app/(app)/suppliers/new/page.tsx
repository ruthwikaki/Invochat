
import { SupplierForm } from '@/components/suppliers/supplier-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function NewSupplierPage() {
  return (
    <AppPage>
        <AppPageHeader
            title="Add New Supplier"
            description="Enter the details for your new supplier."
        />
        <div className="mt-6">
            <SupplierForm />
        </div>
    </AppPage>
  );
}
