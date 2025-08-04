
'use server';
import { NextRequest, NextResponse } from 'next/server';
import { getServiceRoleClient } from '@/lib/supabase/admin';
import { getAuthContext } from '@/lib/auth-helpers';
import { headers } from 'next/headers';
import { logger } from '@/lib/logger';

async function verifyTestAuth(): Promise<boolean> {
    const testApiKey = process.env.TESTING_API_KEY;
    if (!testApiKey || process.env.NODE_ENV === 'production') {
        return false;
    }

    const authHeader = headers().get('Authorization');
    if (!authHeader || authHeader !== `Bearer ${testApiKey}`) {
        return false;
    }
    
    return true;
}

export async function GET(request: NextRequest) {
    if (!(await verifyTestAuth())) {
        return NextResponse.json({ error: 'Forbidden' }, { status: 403 });
    }

    try {
        const { companyId } = await getAuthContext();
        const supabase = getServiceRoleClient();

        const { data: revenueData, error: revenueError } = await supabase
            .from('orders')
            .select('total_amount')
            .eq('company_id', companyId)
            .eq('financial_status', 'paid');
            
        if (revenueError) throw revenueError;

        const totalRevenue = revenueData.reduce((sum, order) => sum + order.total_amount, 0);

        return NextResponse.json({
            totalRevenue,
        });

    } catch (e: any) {
        logger.error('Debug API failed', { error: e.message });
        return NextResponse.json({ error: e.message }, { status: 500 });
    }
}
