
import { NextRequest, NextResponse } from 'next/server';
import { dismissAlert } from '@/services/alert-service';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function POST(_request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const { alertId } = await _request.json();
    
    await dismissAlert(alertId, companyId);
    
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}


