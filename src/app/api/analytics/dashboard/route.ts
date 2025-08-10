
import { NextRequest, NextResponse } from 'next/server';
import { getDashboardMetrics } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export const dynamic = 'force-dynamic';

export async function GET(req: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const { searchParams } = new URL(req.url);
    const range = searchParams.get('range') || '90d';
    
    const data = await getDashboardMetrics(companyId, range);
    
    return NextResponse.json(data);
  } catch (error) {
    const errorMessage = getErrorMessage(error);
    if (errorMessage.includes('Unauthorized') || errorMessage.includes('Authentication required')) {
        return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
    }
    return NextResponse.json({ error: errorMessage }, { status: 500 });
  }
}
