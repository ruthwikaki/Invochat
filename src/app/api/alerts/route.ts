
import { NextRequest, NextResponse } from 'next/server';
import { getCompanyAlerts } from '@/services/alert-service';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function GET(request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const alerts = await getCompanyAlerts(companyId);
    
    return NextResponse.json({ alerts });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}
