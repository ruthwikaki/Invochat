
import { AppPageHeader } from "@/components/ui/page";
import { ExportDataClientPage } from "./_components/export-data-client-page";

export default function ExportDataPage() {
    return (
        <div className="space-y-6">
            <AppPageHeader 
                title="Export Data"
                description="Request a full export of your company's data in CSV format."
            />
            <ExportDataClientPage />
        </div>
    )
}

    