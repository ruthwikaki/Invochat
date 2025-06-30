
import { getLocations } from '@/app/data-actions';
import { LocationsClientPage } from '@/components/locations/locations-client-page';
import { AppPage, AppPageHeader } from '@/components/ui/page';
import { Button } from '@/components/ui/button';
import { Plus } from 'lucide-react';
import Link from 'next/link';

export default async function LocationsPage() {
  const locations = await getLocations();

  return (
    <AppPage className="flex flex-col h-full">
      <AppPageHeader
        title="Locations"
        description="Manage your warehouses and other stock locations."
      >
        <Button asChild>
          <Link href="/locations/new">
            <Plus className="mr-2 h-4 w-4" />
            New Location
          </Link>
        </Button>
      </AppPageHeader>
      <LocationsClientPage initialLocations={locations} />
    </AppPage>
  );
}
