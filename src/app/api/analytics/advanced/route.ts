import { NextRequest, NextResponse } from 'next/server';
import { requireUser, requireCompanyId } from '@/lib/api-auth';
import { 
    getAbcAnalysisFromDB,
    getDemandForecastFromDB, 
    getSalesVelocityFromDB,
    getGrossMarginAnalysisFromDB,
    getHiddenRevenueOpportunitiesFromDB,
    getSupplierPerformanceScoreFromDB,
    getInventoryTurnoverAnalysisFromDB,
    getCustomerBehaviorInsightsFromDB,
    getMultiChannelFeeAnalysisFromDB
} from '@/services/database';

export async function GET(req: NextRequest) {
    try {
        const { user } = await requireUser(req);
        const companyId = requireCompanyId(user);

        const { searchParams } = new URL(req.url);
        const type = searchParams.get('type');

        switch (type) {
            case 'abc-analysis':
                const abcData = await getAbcAnalysisFromDB(companyId);
                return NextResponse.json({ data: abcData });

            case 'demand-forecast':
                const forecastData = await getDemandForecastFromDB(companyId);
                return NextResponse.json({ data: forecastData });

            case 'sales-velocity':
                const days = parseInt(searchParams.get('days') || '30');
                const limit = parseInt(searchParams.get('limit') || '50');
                const velocityData = await getSalesVelocityFromDB(companyId, days, limit);
                return NextResponse.json({ data: velocityData });

            case 'gross-margin':
                const marginData = await getGrossMarginAnalysisFromDB(companyId);
                return NextResponse.json({ data: marginData });

            case 'hidden-opportunities':
                const opportunitiesData = await getHiddenRevenueOpportunitiesFromDB(companyId);
                return NextResponse.json({ data: opportunitiesData });

            case 'supplier-performance':
                const supplierData = await getSupplierPerformanceScoreFromDB(companyId);
                return NextResponse.json({ data: supplierData });

            case 'inventory-turnover':
                const turnoverDays = parseInt(searchParams.get('days') || '365');
                const turnoverData = await getInventoryTurnoverAnalysisFromDB(companyId, turnoverDays);
                return NextResponse.json({ data: turnoverData });

            case 'customer-insights':
                const customerData = await getCustomerBehaviorInsightsFromDB(companyId);
                return NextResponse.json({ data: customerData });

            case 'channel-fees':
                const channelData = await getMultiChannelFeeAnalysisFromDB(companyId);
                return NextResponse.json({ data: channelData });

            default:
                return NextResponse.json({ error: 'Invalid analysis type' }, { status: 400 });
        }
    } catch (error) {
        console.error('Advanced analytics API error:', error);
        return NextResponse.json(
            { error: 'Failed to fetch analytics data' },
            { status: 500 }
        );
    }
}
