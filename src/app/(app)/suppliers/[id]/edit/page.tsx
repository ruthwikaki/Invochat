
import { getSupplierById } from '@/app/data-actions';
import { SupplierForm } from '@/components/suppliers/supplier-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { notFound } from 'next/navigation';

export default async function EditSupplierPage({ params }: { params: { id: string } }) {
  const supplier = await getSupplierById(params.id);

  if (!supplier) {
    notFound();
  }

  return (
    <AppPage>
      <AppPageHeader
        title={`Edit ${supplier.name}`}
        description="Update the details for this supplier."
      />
      <SupplierForm initialData={supplier} />
    </AppPage>
  );
}
