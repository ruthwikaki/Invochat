import { AppPage, AppPageHeader } from "@/components/ui/page";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Package } from "lucide-react";

export default function LocationsPage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Locations"
                description="Manage your warehouses, stores, and other inventory locations."
            />
             <Card className="flex flex-col items-center justify-center text-center p-12 border-2 border-dashed">
                <div className="relative bg-primary/10 rounded-full p-6">
                    <Package className="h-16 w-16 text-primary" />
                </div>
                <h3 className="mt-6 text-xl font-semibold">Coming Soon</h3>
                <p className="mt-2 text-muted-foreground max-w-md">
                    Full multi-location management is under construction. For now, locations can be imported via CSV or managed directly in the database.
                </p>
            </Card>
        </AppPage>
    );
}
