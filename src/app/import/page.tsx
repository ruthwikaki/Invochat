
import { AppPageHeader } from "@/components/ui/page";
import { ImporterClientPage } from "./importer-client-page";
import { generateCSRFToken } from "@/lib/csrf";

export default async function ImportPage() {
    // Generate the CSRF token on the server so the client component can read it from the cookie.
    await generateCSRFToken();

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
