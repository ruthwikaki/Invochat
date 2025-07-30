
import { NextRequest, NextResponse } from 'next/server';
import { AlertService } from '@/services/alert-service';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function GET(request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const alertService = new AlertService();
    const settings = await alertService.getAlertSettings(companyId);
    
    return NextResponse.json({ settings });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const { settings } = await request.json();
    const alertService = new AlertService();
    
    await alertService.updateAlertSettings(companyId, settings);
    
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}
