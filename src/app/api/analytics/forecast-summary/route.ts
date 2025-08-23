import { NextRequest, NextResponse } from 'next/server';
import { requireUser } from '@/lib/api-auth';
import { enhancedForecastingService } from '@/services/enhanced-demand-forecasting';
import { logError } from '@/lib/error-handler';

export async function GET(request: NextRequest) {
  try {
    const { user } = await requireUser(request);

    const summary = await enhancedForecastingService.generateCompanyForecastSummary(
      user.id // Use user.id as company identifier
    );

    return NextResponse.json({
      success: true,
      data: summary
    });

  } catch (error: any) {
    logError(error, { context: 'Company forecast summary API error' });
    return NextResponse.json(
      { error: 'Failed to generate company forecast summary', details: error.message },
      { status: 500 }
    );
  }
}
