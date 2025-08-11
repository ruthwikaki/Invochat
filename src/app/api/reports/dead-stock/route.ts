
import { NextResponse } from 'next/server';
import { getDeadStockReportFromDB } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function GET() {
    try {
        const { companyId } = await getAuthContext();
        const data = await getDeadStockReportFromDB(companyId);
        return NextResponse.json(data);
    } catch(e) {
        const error = getErrorMessage(e);
        if (error.includes('Unauthorized')) {
            return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
        }
        return NextResponse.json({ error }, { status: 500 });
    }
}
