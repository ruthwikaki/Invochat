
import { NextRequest, NextResponse } from 'next/server';
import { AlertService } from '@/services/alert-service';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function GET(request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const alertService = new AlertService();
    const alerts = await alertService.getCompanyAlerts(companyId);
    
    return NextResponse.json({ alerts });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}
