
'use server';

import { getAuthContext } from "@/lib/auth-helpers";
import { invalidateCompanyCache } from "@/lib/redis";
import { refreshMaterializedViews } from "@/services/database";

export async function refreshData() {
    const { companyId } = await getAuthContext();
    await refreshMaterializedViews(companyId);
    await invalidateCompanyCache(companyId, ['dashboard', 'alerts', 'deadstock', 'inventory', 'suppliers']);
}
<<<<<<< HEAD
=======

    
>>>>>>> 6168ea0773980b7de6d6d789337dd24b18126f79
