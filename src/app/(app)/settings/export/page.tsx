import { AppPage, AppPageHeader } from "@/components/ui/page";
import { ExportDataClientPage } from "./_components/export-data-client-page";

export default function ExportDataPage() {
    return (
        <AppPage>
            <AppPageHeader
                title="Export Data"
                description="Request a full export of your company's data in CSV format."
            />
            <div className="mt-6">
                <ExportDataClientPage />
            </div>
        </AppPage>
    )
}
