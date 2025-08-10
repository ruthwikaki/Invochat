
import { NextRequest, NextResponse } from 'next/server';
import { getDashboardMetrics } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage, logError } from '@/lib/error-handler';
import { createRouteHandlerClient } from '@supabase/auth-helpers-nextjs';
import { cookies } from 'next/headers';
import type { Database } from '@/types/database.types';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const supabase = createRouteHandlerClient<Database>({ cookies });

    const { data: { user } } = await supabase.auth.getUser();
    if (!user) {
      return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }

    const companyId = user.app_metadata.company_id;
    if (!companyId) {
      return NextResponse.json({ error: 'User is not associated with a company.' }, { status: 403 });
    }
    
    const { searchParams } = new URL(req.url);
    const range = searchParams.get('range') || '90d';
    
    const data = await getDashboardMetrics(companyId, range);
    
    return NextResponse.json(data);
  } catch (error: unknown) {
    const errorMessage = getErrorMessage(error);
    logError(error, { context: 'API /api/analytics/dashboard' });

    if (errorMessage.includes('Unauthorized')) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
    return NextResponse.json({ error: errorMessage }, { status: 500 });
  }
}
