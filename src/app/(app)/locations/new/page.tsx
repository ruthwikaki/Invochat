
import { LocationForm } from '@/components/locations/location-form';
import { AppPage, AppPageHeader } from '@/components/ui/page';

export default function NewLocationPage() {
  return (
    <AppPage>
      <AppPageHeader
        title="Create New Location"
        description="Add a new warehouse or stock location to your system."
      />
      <LocationForm />
    </AppPage>
  );
}
