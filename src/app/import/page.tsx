
import { AppPageHeader } from "@/components/ui/page";
import { ImporterClientPage } from "./importer-client-page";

export default async function ImportPage() {
    // The CSRF token is now generated on the client-side by calling an API route.
    // This prevents the app from crashing by attempting to set a cookie during server-side rendering.
    return (
        <>
            <AppPageHeader 
                title="Data Importer"
                description="Bulk import your data from CSV files."
            />
            <ImporterClientPage />
        </>
    )
}
