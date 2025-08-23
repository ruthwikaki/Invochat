import { NextResponse } from 'next/server';
import { getAbcAnalysisFromDB } from '@/services/database';
import { getAuthContext } from '@/lib/auth-helpers';

export async function POST() {
    try {
        const authContext = await getAuthContext();
        
        const abcData = await getAbcAnalysisFromDB(authContext.companyId);
        
        if (!abcData) {
            return NextResponse.json(
                { error: 'Failed to retrieve ABC analysis data' },
                { status: 500 }
            );
        }

        return NextResponse.json({
            success: true,
            products: abcData,
            summary: {
                total_products: abcData.length,
                category_distribution: {
                    A: abcData.filter(p => p.category === 'A').length,
                    B: abcData.filter(p => p.category === 'B').length,
                    C: abcData.filter(p => p.category === 'C').length,
                },
                analysis_date: new Date().toISOString(),
            }
        });
    } catch (error) {
        console.error('ABC Analysis API error:', error);
        return NextResponse.json(
            { error: error instanceof Error ? error.message : 'Failed to analyze inventory' },
            { status: 500 }
        );
    }
}
