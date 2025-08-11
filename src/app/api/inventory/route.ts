
import { NextRequest, NextResponse } from 'next/server';
import { createServerClient } from '@/lib/supabase/admin';
import type { Database } from '@/types/database.types';
import { getUnifiedInventoryFromDB } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function GET(req: NextRequest) {
    try {
        const { companyId } = await getAuthContext();

        const { searchParams } = new URL(req.url);
        const page  = Math.max(1, Number(searchParams.get('page') ?? 1));
        const limit = Math.min(100, Math.max(1, Number(searchParams.get('limit') ?? 10)));
        const status = searchParams.get('status') || 'all';
        const query = searchParams.get('query') || '';

        const data = await getUnifiedInventoryFromDB(companyId, { page, limit, status, query });

        return NextResponse.json(data);
    } catch(e) {
        const error = getErrorMessage(e);
        if (error.includes('Unauthorized')) {
            return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
        }
        return NextResponse.json({ error }, { status: 500 });
    }
}
