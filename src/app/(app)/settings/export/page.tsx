
import { AppPageContainer } from "@/components/ui/page";
import { ExportDataClientPage } from "./_components/export-data-client-page";

export default function ExportDataPage() {
    return (
        <AppPageContainer
            title="Export Data"
            description="Request a full export of your company's data in CSV format."
        >
            <ExportDataClientPage />
        </AppPageContainer>
    )
}
