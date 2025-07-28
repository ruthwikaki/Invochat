
import { AppPage, AppPageHeader } from "@/components/ui/page";
import { getAuditLogData } from "@/app/data-actions";
import { AuditLogClientPage } from "./audit-log-client-page";

export const dynamic = 'force-dynamic';

const ITEMS_PER_PAGE = 25;

export default async function AuditLogPage({
  searchParams,
}: {
  searchParams: { [key: string]: string | string[] | undefined };
}) {
    const page = Number(searchParams?.page) || 1;
    const query = searchParams?.query?.toString() || '';

    const auditLogData = await getAuditLogData({ page, limit: ITEMS_PER_PAGE, query });
    
    return (
        <AppPage>
            <AppPageHeader
                title="Audit Log"
                description="Review a complete history of all significant actions taken in your account."
            />
            <div className="mt-6">
                <AuditLogClientPage 
                    initialData={auditLogData.items}
                    totalCount={auditLogData.totalCount}
                    itemsPerPage={ITEMS_PER_PAGE}
                />
            </div>
        </AppPage>
    );
}
