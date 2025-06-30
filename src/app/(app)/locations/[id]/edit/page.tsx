
import { getLocationById } from '@/app/data-actions';
import { LocationForm } from '@/components/locations/location-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { notFound } from 'next/navigation';

export default async function EditLocationPage({ params }: { params: { id: string } }) {
  const location = await getLocationById(params.id);

  if (!location) {
    notFound();
  }

  return (
    <AppPage>
      <AppPageHeader
        title={`Edit ${location.name}`}
        description="Update the details for this location."
      />
      <LocationForm initialData={location} />
    </AppPage>
  );
}
