import { AppPage, AppPageHeader } from "@/components/ui/page";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { MapPin } from "lucide-react";

export default function LocationsPage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Locations"
                description="Manage your inventory storage locations."
            />
             <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
                <div className="relative bg-primary/10 rounded-full p-6">
                    <MapPin className="h-16 w-16 text-primary" />
                </div>
                <h3 className="mt-6 text-xl font-semibold">Simplified Location Management</h3>
                <p className="mt-2 text-muted-foreground max-w-md">
                    Multi-warehouse management has been simplified. You can now specify a storage location (e.g., "Bin A-4") for each product variant directly in your imported data. This page is for future enhancements.
                </p>
            </Card>
        </AppPage>
    );
}
