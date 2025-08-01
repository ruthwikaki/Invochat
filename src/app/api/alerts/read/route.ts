
import { NextRequest, NextResponse } from 'next/server';
import { markAlertAsRead } from '@/services/alert-service';
import { getAuthContext } from '@/lib/auth-helpers';
import { getErrorMessage } from '@/lib/error-handler';

export async function POST(request: NextRequest) {
  try {
    const { companyId } = await getAuthContext();
    const { alertId } = await request.json();
    
    await markAlertAsRead(alertId, companyId);
    
    return NextResponse.json({ success: true });
  } catch (error) {
    return NextResponse.json({ error: getErrorMessage(error) }, { status: 500 });
  }
}
