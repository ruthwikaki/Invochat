
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { ImporterClientPage } from "./importer-client-page";
import { generateCSRFToken } from "@/lib/csrf";

export default function ImportPage() {
    // Generate the CSRF token on the server so the client component can read it from the cookie.
    generateCSRFToken();

    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Data Importer"
                description="Bulk import your data from CSV files."
            />
            <ImporterClientPage />
        </div>
    )
}

