import { AppPage, AppPageHeader } from "@/components/ui/page";

export default function LocationsPage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Locations"
                description="Manage your warehouses, stores, and other inventory locations."
            />
            <div className="text-center py-16 border-2 border-dashed rounded-lg">
                <h3 className="text-lg font-semibold">Coming Soon</h3>
                <p className="text-sm text-muted-foreground">
                    This page is under construction. Locations can currently be managed via data import.
                </p>
            </div>
        </AppPage>
    );
}
