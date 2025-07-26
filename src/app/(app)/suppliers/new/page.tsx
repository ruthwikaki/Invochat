
import { SupplierForm } from '@/components/suppliers/supplier-form';
import { AppPageContainer } from '@/components/ui/page';

export default function NewSupplierPage() {
  return (
    <AppPageContainer
      title="Add New Supplier"
      description="Enter the details for your new supplier."
    >
      <SupplierForm />
    </AppPageContainer>
  );
}
