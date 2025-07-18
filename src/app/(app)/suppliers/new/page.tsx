
import { SupplierForm } from '@/components/suppliers/supplier-form';
import { AppPageHeader } from '@/components/ui/page';

export default function NewSupplierPage() {
  return (
    <div className="space-y-6">
      <AppPageHeader
        title="Add New Supplier"
        description="Enter the details for your new supplier."
      />
      <SupplierForm />
    </div>
  );
}
